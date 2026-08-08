import XCTest
@testable import MacYoutubeUploader

@MainActor
final class UploadStoreRetryTests: XCTestCase {
    func testStartQueueRequiresAcceptedPolicies() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockUploadPreferences()
        preferences.hasAcceptedRequiredPolicies = false
        let uploader = UploadVideoSpy(results: [
            .success(YouTubeUploadResult(videoID: "unexpected", playlistID: nil, playlistErrorDescription: nil))
        ])
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
            activity: UploadActivitySpy()
        )

        store.enqueue([sourceURL])
        store.startQueuedUploads()

        XCTAssertEqual(store.errorMessage, AppError.legalAgreementRequired.localizedDescription)
        XCTAssertEqual(store.jobs.first?.phase, .queued)
        XCTAssertTrue(uploader.uploadedFileURLs.isEmpty)
    }

    func testUpdateQueuedJobMetadataBeforeUpload() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockUploadPreferences()
        let store = UploadStore(preferences: preferences, activity: UploadActivitySpy())

        store.enqueue([sourceURL])
        let jobID = try XCTUnwrap(store.jobs.first?.id)
        let editedMetadata = UploadMetadata(
            title: "Reviewed title",
            description: "Reviewed description",
            tags: ["reviewed", "upload"],
            categoryID: "27",
            privacy: .unlisted,
            madeForKids: true,
            allowEmbedding: false
        )

        store.updateJob(
            id: jobID,
            metadata: editedMetadata,
            selectedChannelID: preferences.selectedChannelID,
            selectedPlaylistID: nil
        )

        XCTAssertEqual(store.jobs.first?.metadata, editedMetadata)
        XCTAssertEqual(store.jobs.first?.selectedChannelID, preferences.selectedChannelID)
    }

    func testCancelQueuedJobMarksJobCancelledAndDoesNotUpload() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockUploadPreferences()
        let uploader = UploadVideoSpy(results: [
            .success(YouTubeUploadResult(videoID: "unexpected", playlistID: nil, playlistErrorDescription: nil))
        ])
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
            activity: UploadActivitySpy()
        )

        store.enqueue([sourceURL])
        let jobID = try XCTUnwrap(store.jobs.first?.id)

        store.cancel(jobID: jobID)
        XCTAssertEqual(store.jobs.first?.phase, .cancelled)

        store.startQueuedUploads()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.jobs.first?.phase, .cancelled)
        XCTAssertTrue(uploader.uploadedFileURLs.isEmpty)
    }

    func testCancelRunningJobCancelsUploadTask() async throws {
        let sourceURL = try makeTemporaryVideo()
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let preferences = MockUploadPreferences()
        let uploader = CancellableUploadSpy()
        let activity = UploadActivitySpy()
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
            activity: activity
        )

        store.enqueue([sourceURL])
        let jobID = try XCTUnwrap(store.jobs.first?.id)
        store.startQueuedUploads()

        try await waitForStore(store) { _ in
            uploader.didStart
        }

        store.cancel(jobID: jobID)
        try await waitForStore(store) { store in
            store.jobs.first?.phase == .cancelled
        }

        XCTAssertTrue(uploader.wasCancelled)
        XCTAssertEqual(activity.endCount, 1)
    }

    func testStartQueueRetriesFailedChunkJobUsingExistingAssembly() async throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStoreRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let sourceURLs = [
            sourceDirectory.appendingPathComponent("clip_001.mov"),
            sourceDirectory.appendingPathComponent("clip_002.mov")
        ]
        for url in sourceURLs {
            try Data([0, 1, 2, 3]).write(to: url)
        }

        let assembledDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacYouTubeUploader", isDirectory: true)
        try FileManager.default.createDirectory(at: assembledDirectory, withIntermediateDirectories: true)
        let assembledURL = assembledDirectory.appendingPathComponent("cached-\(UUID().uuidString).mov")
        try Data([4, 5, 6, 7]).write(to: assembledURL)
        defer { try? FileManager.default.removeItem(at: assembledURL) }

        let preferences = MockUploadPreferences()
        let assembler = UploadAssemblySpy(assembledURL: assembledURL)
        let uploader = UploadVideoSpy(results: [
            .failure(UploadStoreRetryTestError.uploadFailed),
            .success(YouTubeUploadResult(videoID: "video-123", playlistID: nil, playlistErrorDescription: nil))
        ])

        let store = UploadStore(
            preferences: preferences,
            assembleUploadFile: { sourceURLs, titleSeed, onProgress in
                try await assembler.assemble(
                    sourceURLs: sourceURLs,
                    titleSeed: titleSeed,
                    onProgress: onProgress
                )
            },
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
            activity: UploadActivitySpy()
        )

        store.enqueue(sourceURLs)
        XCTAssertEqual(store.jobs.first?.chunkCount, 2)

        store.startQueuedUploads()
        try await waitForStore(store) { store in
            guard case .failed = store.jobs.first?.phase else { return false }
            return true
        }

        XCTAssertEqual(assembler.callCount, 1)
        XCTAssertEqual(uploader.uploadedFileURLs, [assembledURL])
        XCTAssertEqual(store.jobs.first?.assembledFileURL, assembledURL)

        store.startQueuedUploads()
        try await waitForStore(store) { store in
            guard case .completed(let videoID) = store.jobs.first?.phase else { return false }
            return videoID == "video-123"
        }

        XCTAssertEqual(assembler.callCount, 1)
        XCTAssertEqual(uploader.uploadedFileURLs, [assembledURL, assembledURL])
        XCTAssertNil(store.errorMessage)
    }

    private func waitForStore(
        _ store: UploadStore,
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor (UploadStore) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition(store) {
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
private final class MockUploadPreferences: UploadPreferencesProviding {
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
private final class UploadAssemblySpy {
    private let assembledURL: URL
    private(set) var callCount = 0

    init(assembledURL: URL) {
        self.assembledURL = assembledURL
    }

    func assemble(
        sourceURLs: [URL],
        titleSeed: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        callCount += 1
        onProgress(1)
        return assembledURL
    }
}

@MainActor
private final class UploadVideoSpy {
    enum Result {
        case success(YouTubeUploadResult)
        case failure(Error)
    }

    private var results: [Result]
    private(set) var uploadedFileURLs: [URL] = []

    init(results: [Result]) {
        self.results = results
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
        onProgress(0.5)

        switch results.removeFirst() {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
private final class CancellableUploadSpy {
    private(set) var didStart = false
    private(set) var wasCancelled = false

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
        onProgress(0.25)

        do {
            while true {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        } catch is CancellationError {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

@MainActor
private final class UploadActivitySpy: UploadActivityControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin(keepMacAwake: Bool) {
        beginCount += 1
    }

    func end() {
        endCount += 1
    }
}

private enum UploadStoreRetryTestError: LocalizedError {
    case uploadFailed

    var errorDescription: String? {
        "Temporary upload failure"
    }
}
