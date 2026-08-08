import XCTest
@testable import MacYoutubeUploader

@MainActor
final class UploadStoreInterruptedPromptTests: XCTestCase {
    private var queueFileURL: URL!
    private var sourceDirectory: URL!

    override func setUp() {
        super.setUp()
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UploadStoreInterruptedPromptTests-\(UUID().uuidString)", isDirectory: true)
        queueFileURL = testDirectory.appendingPathComponent("UploadQueue.json")
        sourceDirectory = testDirectory.appendingPathComponent("sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: queueFileURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testRestoringInterruptedJobsShowsPrompt() throws {
        let preferences = MockPromptPreferences()
        try writeQueueFixture(
            interruptedCount: 2,
            queuedCount: 1,
            channelID: preferences.selectedChannelID
        )

        let store = makeStore(preferences: preferences, uploader: GatedPromptUploadSpy())

        XCTAssertTrue(store.showsInterruptedUploadsPrompt)
        XCTAssertEqual(store.interruptedCount, 2)
        XCTAssertEqual(store.queuedCount, 1)
    }

    func testRestoringWithoutInterruptedJobsHidesPrompt() throws {
        let preferences = MockPromptPreferences()
        try writeQueueFixture(
            interruptedCount: 0,
            queuedCount: 2,
            channelID: preferences.selectedChannelID
        )

        let store = makeStore(preferences: preferences, uploader: GatedPromptUploadSpy())

        XCTAssertFalse(store.showsInterruptedUploadsPrompt)
        XCTAssertEqual(store.interruptedCount, 0)
    }

    func testResumeInterruptedUploadsRequiresAcceptedPolicies() throws {
        let preferences = MockPromptPreferences()
        preferences.hasAcceptedRequiredPolicies = false
        try writeQueueFixture(
            interruptedCount: 1,
            queuedCount: 0,
            channelID: preferences.selectedChannelID
        )

        let uploader = GatedPromptUploadSpy()
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.resumeInterruptedUploads()

        XCTAssertEqual(store.errorMessage, AppError.legalAgreementRequired.localizedDescription)
        XCTAssertEqual(store.jobs.first?.phase, .interrupted)
        XCTAssertEqual(uploader.startedCount, 0)
        XCTAssertTrue(store.showsInterruptedUploadsPrompt, "The prompt stays up so the user can resume after accepting.")
    }

    func testResumeInterruptedUploadsLeavesFailedJobsAlone() async throws {
        let preferences = MockPromptPreferences()
        try writeQueueFixture(
            interruptedCount: 1,
            queuedCount: 0,
            failedCount: 1,
            channelID: preferences.selectedChannelID
        )

        let uploader = GatedPromptUploadSpy()
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.resumeInterruptedUploads()
        XCTAssertFalse(store.showsInterruptedUploadsPrompt)

        uploader.releaseAll()
        try await waitFor { store.completedCount == 1 }

        XCTAssertEqual(uploader.startedCount, 1)
        XCTAssertEqual(store.failedCount, 1, "Resume must not restart failed jobs.")
        XCTAssertEqual(store.interruptedCount, 0)
    }

    func testResumeInterruptedUploadsRespectsMaxConcurrentUploads() async throws {
        let preferences = MockPromptPreferences()
        preferences.maxConcurrentUploads = 2
        try writeQueueFixture(
            interruptedCount: 3,
            queuedCount: 0,
            channelID: preferences.selectedChannelID
        )

        let uploader = GatedPromptUploadSpy()
        let store = makeStore(preferences: preferences, uploader: uploader)

        store.resumeInterruptedUploads()
        try await waitFor { uploader.startedCount == 2 }

        // Give the store a chance to (incorrectly) start more than the limit.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(uploader.startedCount, 2)
        XCTAssertEqual(store.queuedCount, 1)

        uploader.releaseAll()
        try await waitFor { store.completedCount == 3 }
        XCTAssertEqual(uploader.maxObservedConcurrency, 2)
    }

    func testDismissHidesPromptWithoutTouchingJobs() throws {
        let preferences = MockPromptPreferences()
        try writeQueueFixture(
            interruptedCount: 1,
            queuedCount: 0,
            channelID: preferences.selectedChannelID
        )

        let store = makeStore(preferences: preferences, uploader: GatedPromptUploadSpy())

        store.dismissInterruptedUploadsPrompt()

        XCTAssertFalse(store.showsInterruptedUploadsPrompt)
        XCTAssertEqual(store.interruptedCount, 1, "Dismissing only hides the banner; jobs stay interrupted.")
    }

    private func makeStore(
        preferences: MockPromptPreferences,
        uploader: GatedPromptUploadSpy
    ) -> UploadStore {
        UploadStore(
            preferences: preferences,
            uploadVideoFile: { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
                try await uploader.upload(fileURL: fileURL, onProgress: onProgress)
            },
            activity: PromptActivitySpy(),
            persistence: UploadQueuePersistence(fileURL: queueFileURL, debounceInterval: 0)
        )
    }

    private func writeQueueFixture(
        interruptedCount: Int,
        queuedCount: Int,
        failedCount: Int = 0,
        channelID: String?
    ) throws {
        var jobs: [UploadJob] = []

        func makeJob(named name: String) throws -> UploadJob {
            let sourceURL = sourceDirectory.appendingPathComponent("\(name).mov")
            try Data([0, 1, 2, 3]).write(to: sourceURL)
            return UploadJob(
                sourceURLs: [sourceURL],
                titleSeed: name,
                metadata: MetadataDefaults().uploadMetadata(for: name),
                selectedChannelID: channelID,
                selectedPlaylistID: nil
            )
        }

        for index in 0..<interruptedCount {
            var job = try makeJob(named: "interrupted-\(index)")
            job.phase = .uploading
            job.progress = 0.5
            jobs.append(job)
        }
        for index in 0..<queuedCount {
            jobs.append(try makeJob(named: "queued-\(index)"))
        }
        for index in 0..<failedCount {
            var job = try makeJob(named: "failed-\(index)")
            job.phase = .failed("Earlier upload error")
            jobs.append(job)
        }

        try FileManager.default.createDirectory(
            at: queueFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(jobs).write(to: queueFileURL)
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
private final class MockPromptPreferences: UploadPreferencesProviding {
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
private final class GatedPromptUploadSpy {
    private(set) var startedCount = 0
    private(set) var maxObservedConcurrency = 0
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func upload(
        fileURL: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> YouTubeUploadResult {
        startedCount += 1
        activeCount += 1
        maxObservedConcurrency = max(maxObservedConcurrency, activeCount)
        onProgress(0.5)

        if !isReleased {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        activeCount -= 1
        return YouTubeUploadResult(videoID: "video-\(startedCount)", playlistID: nil, playlistErrorDescription: nil)
    }

    func releaseAll() {
        isReleased = true
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
private final class PromptActivitySpy: UploadActivityControlling {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func begin(keepMacAwake: Bool) {
        beginCount += 1
    }

    func end() {
        endCount += 1
    }
}
