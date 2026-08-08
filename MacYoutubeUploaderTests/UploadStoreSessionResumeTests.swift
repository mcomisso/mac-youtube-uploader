import XCTest
@testable import MacYoutubeUploader

@MainActor
final class UploadStoreSessionResumeTests: XCTestCase {
    private static let storedSession = URL(string: "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=stored")!

    private var queueFileURL: URL!

    override func setUp() {
        super.setUp()
        queueFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStoreSessionResumeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("UploadQueue.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: queueFileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makePersistence() -> UploadQueuePersistence {
        UploadQueuePersistence(fileURL: queueFileURL, debounceInterval: 0)
    }

    func testRestoredInterruptedJobPassesStoredSessionToUploader() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockResumePreferences()
        try writeQueueFixture(
            sourceURL: sourceURL,
            channelID: preferences.selectedChannelID,
            resumableFileSize: sourceURL.fileSize
        )

        let uploader = SessionCapturingUploadSpy()
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.startQueuedUploads()
        try await waitFor { store.completedCount == 1 }

        XCTAssertEqual(uploader.capturedResumeSessionURLs, [Self.storedSession])
    }

    func testRestoredJobIgnoresStoredSessionWhenFileSizeChanged() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockResumePreferences()
        try writeQueueFixture(
            sourceURL: sourceURL,
            channelID: preferences.selectedChannelID,
            resumableFileSize: 999
        )

        let uploader = SessionCapturingUploadSpy()
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.startQueuedUploads()
        try await waitFor { store.completedCount == 1 }

        XCTAssertEqual(uploader.capturedResumeSessionURLs, [nil])
    }

    func testEstablishedSessionIsPersistedAndClearedOnCompletion() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockResumePreferences()
        let uploader = SessionCapturingUploadSpy(
            establishSessionURL: Self.storedSession,
            blocksUntilReleased: true
        )
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.enqueue([sourceURL])
        store.startQueuedUploads()

        try await waitFor { store.jobs.first?.resumableSessionURL == Self.storedSession }
        XCTAssertEqual(store.jobs.first?.resumableFileSize, sourceURL.fileSize)

        // What a crash at this moment would leave on disk: the session URL
        // alongside the interrupted marker.
        let persisted = try JSONDecoder().decode(
            [UploadJob].self,
            from: Data(contentsOf: queueFileURL)
        )
        XCTAssertEqual(persisted.first?.resumableSessionURL, Self.storedSession)
        XCTAssertEqual(persisted.first?.phase, .interrupted)

        uploader.release()
        try await waitFor { store.completedCount == 1 }

        XCTAssertNil(store.jobs.first?.resumableSessionURL)
        XCTAssertNil(store.jobs.first?.resumableFileSize)
    }

    private func makeStore(
        preferences: MockResumePreferences,
        uploader: SessionCapturingUploadSpy
    ) -> UploadStore {
        UploadStore(
            preferences: preferences,
            uploadVideoFile: { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
                try await uploader.upload(
                    fileURL: fileURL,
                    resumeSessionURL: resumeSessionURL,
                    onSessionEstablished: onSessionEstablished,
                    onProgress: onProgress
                )
            },
            activity: ResumeActivitySpy(),
            persistence: makePersistence()
        )
    }

    private func writeQueueFixture(
        sourceURL: URL,
        channelID: String?,
        resumableFileSize: Int64?
    ) throws {
        var job = UploadJob(
            sourceURLs: [sourceURL],
            titleSeed: "fixture",
            metadata: MetadataDefaults().uploadMetadata(for: "fixture"),
            selectedChannelID: channelID,
            selectedPlaylistID: nil
        )
        job.phase = .uploading
        job.progress = 0.4
        job.resumableSessionURL = Self.storedSession
        job.resumableFileSize = resumableFileSize

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
private final class MockResumePreferences: UploadPreferencesProviding {
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
private final class SessionCapturingUploadSpy {
    private let establishSessionURL: URL?
    private let blocksUntilReleased: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var capturedResumeSessionURLs: [URL?] = []

    init(establishSessionURL: URL? = nil, blocksUntilReleased: Bool = false) {
        self.establishSessionURL = establishSessionURL
        self.blocksUntilReleased = blocksUntilReleased
    }

    func upload(
        fileURL: URL,
        resumeSessionURL: URL?,
        onSessionEstablished: @escaping (URL) -> Void,
        onProgress: @escaping (Double) -> Void
    ) async throws -> YouTubeUploadResult {
        capturedResumeSessionURLs.append(resumeSessionURL)
        if let establishSessionURL {
            onSessionEstablished(establishSessionURL)
        }
        onProgress(0.5)

        if blocksUntilReleased {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        return YouTubeUploadResult(videoID: "video-123", playlistID: nil, playlistErrorDescription: nil)
    }

    func release() {
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
private final class ResumeActivitySpy: UploadActivityControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin(keepMacAwake: Bool) {
        beginCount += 1
    }

    func end() {
        endCount += 1
    }
}
