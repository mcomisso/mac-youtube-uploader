import XCTest
@testable import MacYoutubeUploader

@MainActor
final class UploadStorePersistenceTests: XCTestCase {
    private var queueFileURL: URL!

    override func setUp() {
        super.setUp()
        queueFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStorePersistenceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("UploadQueue.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: queueFileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makePersistence() -> UploadQueuePersistence {
        UploadQueuePersistence(fileURL: queueFileURL, debounceInterval: 0)
    }

    func testActivePhasesEncodeAsInterrupted() throws {
        let activePhases: [UploadPhase] = [.preparing, .reconstructing, .uploading, .interrupted]
        for phase in activePhases {
            let decoded = try roundTrip(phase)
            XCTAssertEqual(decoded, .interrupted, "Expected \(phase) to restore as interrupted.")
        }
    }

    func testInactivePhasesRoundTrip() throws {
        let phases: [UploadPhase] = [
            .queued,
            .waitingForAccount,
            .completed(videoID: "video-123"),
            .completed(videoID: nil),
            .failed("Network gave up"),
            .cancelled
        ]
        for phase in phases {
            XCTAssertEqual(try roundTrip(phase), phase)
        }
    }

    func testEnqueuePersistsJobsAndRestoresOnNextLaunch() throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockPersistencePreferences()
        let store = UploadStore(
            preferences: preferences,
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )
        store.enqueue([sourceURL])
        let enqueuedJob = try XCTUnwrap(store.jobs.first)

        let restoredStore = UploadStore(
            preferences: preferences,
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )

        XCTAssertEqual(restoredStore.jobs.count, 1)
        let restoredJob = try XCTUnwrap(restoredStore.jobs.first)
        XCTAssertEqual(restoredJob.id, enqueuedJob.id)
        XCTAssertEqual(restoredJob.phase, .queued)
        XCTAssertEqual(restoredJob.metadata, enqueuedJob.metadata)
        XCTAssertEqual(restoredJob.titleSeed, enqueuedJob.titleSeed)
        XCTAssertEqual(restoredJob.selectedChannelID, enqueuedJob.selectedChannelID)
        XCTAssertEqual(
            restoredJob.sourceURLs.map(\.standardizedFileURL.path),
            enqueuedJob.sourceURLs.map(\.standardizedFileURL.path)
        )
        XCTAssertTrue(restoredJob.sourceURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testUploadingJobIsPersistedAsInterruptedWhileInFlight() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockPersistencePreferences()
        let uploader = BlockingUploadSpy()
        let store = UploadStore(
            preferences: preferences,
            uploadVideoFile: { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
                try await uploader.upload(
                    fileURL: fileURL,
                    metadata: metadata,
                    channel: channel,
                    playlistID: playlistID,
                    oauthConfig: oauthConfig,
                    onProgress: onProgress,
                    onCredentialsRefreshed: onCredentialsRefreshed
                )
            },
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )

        store.enqueue([sourceURL])
        store.startQueuedUploads()
        try await waitFor { uploader.didStart }
        try await waitFor { store.jobs.first?.phase == .uploading }

        // The file written mid-upload is what a crash would leave behind.
        let persisted = try JSONDecoder().decode(
            [UploadJob].self,
            from: Data(contentsOf: queueFileURL)
        )
        XCTAssertEqual(persisted.first?.phase, .interrupted)

        uploader.release()
        try await waitFor { store.completedCount == 1 }
    }

    func testRestoredInterruptedJobUploadsWhenQueueStarts() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockPersistencePreferences()
        try writeQueueFixture(sourceURL: sourceURL, channelID: preferences.selectedChannelID)

        let uploader = SingleResultUploadSpy(
            result: YouTubeUploadResult(videoID: "video-77", playlistID: nil, playlistErrorDescription: nil)
        )
        let store = UploadStore(
            preferences: preferences,
            uploadVideoFile: { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
                try await uploader.upload(
                    fileURL: fileURL,
                    metadata: metadata,
                    channel: channel,
                    playlistID: playlistID,
                    oauthConfig: oauthConfig,
                    onProgress: onProgress,
                    onCredentialsRefreshed: onCredentialsRefreshed
                )
            },
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )

        XCTAssertEqual(store.jobs.first?.phase, .interrupted)

        store.startQueuedUploads()
        try await waitFor {
            store.jobs.first?.phase == .completed(videoID: "video-77")
        }
        XCTAssertEqual(
            uploader.uploadedFileURLs.map(\.standardizedFileURL.path),
            [sourceURL.standardizedFileURL.path]
        )
    }

    func testClearFinishedJobsPersistsRemoval() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockPersistencePreferences()
        let uploader = SingleResultUploadSpy(
            result: YouTubeUploadResult(videoID: "video-1", playlistID: nil, playlistErrorDescription: nil)
        )
        let store = UploadStore(
            preferences: preferences,
            uploadVideoFile: { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
                try await uploader.upload(
                    fileURL: fileURL,
                    metadata: metadata,
                    channel: channel,
                    playlistID: playlistID,
                    oauthConfig: oauthConfig,
                    onProgress: onProgress,
                    onCredentialsRefreshed: onCredentialsRefreshed
                )
            },
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )

        store.enqueue([sourceURL])
        store.startQueuedUploads()
        try await waitFor { store.completedCount == 1 }

        store.clearFinishedJobs()

        let restoredStore = UploadStore(
            preferences: preferences,
            activity: PersistenceActivitySpy(),
            persistence: makePersistence()
        )
        XCTAssertTrue(restoredStore.jobs.isEmpty)
    }

    private func roundTrip(_ phase: UploadPhase) throws -> UploadPhase {
        let data = try JSONEncoder().encode(phase)
        return try JSONDecoder().decode(UploadPhase.self, from: data)
    }

    /// Writes a queue file the way a crashed app would have left it: one job
    /// that was mid-upload, persisted with the interrupted marker.
    private func writeQueueFixture(sourceURL: URL, channelID: String?) throws {
        var job = UploadJob(
            sourceURLs: [sourceURL],
            titleSeed: "fixture",
            metadata: MetadataDefaults().uploadMetadata(for: "fixture"),
            selectedChannelID: channelID,
            selectedPlaylistID: nil
        )
        job.phase = .uploading
        job.progress = 0.4

        try FileManager.default.createDirectory(
            at: queueFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode([job]).write(to: queueFileURL)
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for upload store state.")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private func makeTemporaryVideo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("mov")
    try Data([0, 1, 2, 3]).write(to: url)
    return url
}

@MainActor
private final class MockPersistencePreferences: UploadPreferencesProviding {
    var metadata = MetadataDefaults()
    var selectedChannelID: String? { channel.id }
    var selectedChannel: AuthorizedChannel? { channel }
    var authorizedChannels: [AuthorizedChannel] { [channel] }
    var selectedPlaylistID: String?
    var oauthConfig = OAuthClientConfig(clientID: "client", clientSecret: "")
    var startsUploadsAutomatically = false
    var keepMacAwake = false
    var hasAcceptedRequiredPolicies = true
    var maxConcurrentUploads = 3

    private let channel = AuthorizedChannel(
        id: "channel-1",
        title: "Test Channel",
        handle: nil,
        thumbnailURL: nil,
        credentials: OAuthCredentials(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            tokenType: "Bearer",
            expiresAt: Date().addingTimeInterval(3600),
            scope: nil
        )
    )

    func selectedPlaylistID(for channelID: String) -> String? {
        selectedPlaylistID
    }

    func playlist(id: String, channelID: String) -> YouTubePlaylist? {
        nil
    }

    func updateCredentials(_ credentials: OAuthCredentials, for channelID: String) {}
}

@MainActor
private final class SingleResultUploadSpy {
    private let result: YouTubeUploadResult
    private(set) var uploadedFileURLs: [URL] = []

    init(result: YouTubeUploadResult) {
        self.result = result
    }

    func upload(
        fileURL: URL,
        metadata: UploadMetadata,
        channel: AuthorizedChannel,
        playlistID: String?,
        oauthConfig: OAuthClientConfig,
        onProgress: @escaping (Double) -> Void,
        onCredentialsRefreshed: @escaping (OAuthCredentials) -> Void
    ) async throws -> YouTubeUploadResult {
        uploadedFileURLs.append(fileURL)
        onProgress(1)
        return result
    }
}

@MainActor
private final class BlockingUploadSpy {
    private(set) var didStart = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func upload(
        fileURL: URL,
        metadata: UploadMetadata,
        channel: AuthorizedChannel,
        playlistID: String?,
        oauthConfig: OAuthClientConfig,
        onProgress: @escaping (Double) -> Void,
        onCredentialsRefreshed: @escaping (OAuthCredentials) -> Void
    ) async throws -> YouTubeUploadResult {
        didStart = true
        onProgress(0.4)

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }

        return YouTubeUploadResult(videoID: "video-1", playlistID: nil, playlistErrorDescription: nil)
    }

    func release() {
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
private final class PersistenceActivitySpy: UploadActivityControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin(keepMacAwake: Bool) {
        beginCount += 1
    }

    func end() {
        endCount += 1
    }
}
