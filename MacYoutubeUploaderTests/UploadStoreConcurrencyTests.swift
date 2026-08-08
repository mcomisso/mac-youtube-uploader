import XCTest
@testable import MacYoutubeUploader

@MainActor
final class UploadStoreConcurrencyTests: XCTestCase {
    func testRunsAtMostMaxConcurrentUploadsAndDrainsQueue() async throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStoreConcurrencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        let sourceURLs = try ["alpha", "bravo", "charlie"].map { name in
            let url = sourceDirectory.appendingPathComponent("\(name).mov")
            try Data([0, 1, 2, 3]).write(to: url)
            return url
        }

        let preferences = MockConcurrencyPreferences()
        preferences.maxConcurrentUploads = 2
        let uploader = GatedUploadSpy()
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
            activity: ConcurrencyActivitySpy()
        )

        store.enqueue(sourceURLs)
        XCTAssertEqual(store.jobs.count, 3)

        store.startQueuedUploads()
        try await waitFor { uploader.startedCount == 2 }

        // Give the store a chance to (incorrectly) start more than the limit.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(uploader.startedCount, 2)
        XCTAssertEqual(store.jobs.filter { $0.phase == .queued }.count, 1)

        uploader.releaseOne()
        try await waitFor { uploader.startedCount == 3 }

        uploader.releaseAll()
        try await waitFor { store.completedCount == 3 }

        XCTAssertEqual(uploader.maxObservedConcurrency, 2)
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

@MainActor
private final class GatedUploadSpy {
    private(set) var startedCount = 0
    private(set) var maxObservedConcurrency = 0
    private var activeCount = 0
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
        startedCount += 1
        activeCount += 1
        maxObservedConcurrency = max(maxObservedConcurrency, activeCount)
        onProgress(0.5)

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }

        activeCount -= 1
        return YouTubeUploadResult(videoID: "video-\(startedCount)", playlistID: nil, playlistErrorDescription: nil)
    }

    func releaseOne() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
private final class MockConcurrencyPreferences: UploadPreferencesProviding {
    var metadata = MetadataDefaults()
    var selectedChannelID: String? { channel.id }
    var selectedChannel: AuthorizedChannel? { channel }
    var authorizedChannels: [AuthorizedChannel] { [channel] }
    var selectedPlaylistID: String?
    var oauthConfig = OAuthClientConfig(clientID: "client", clientSecret: "")
    var startsUploadsAutomatically = false
    var keepMacAwake = false
    var hasAcceptedRequiredPolicies = true
    var maxConcurrentUploads = 2

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
private final class ConcurrencyActivitySpy: UploadActivityControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin(keepMacAwake: Bool) {
        beginCount += 1
    }

    func end() {
        endCount += 1
    }
}
