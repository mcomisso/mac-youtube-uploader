import Foundation
import Combine

@MainActor
protocol UploadPreferencesProviding: AnyObject {
    var metadata: MetadataDefaults { get }
    var selectedChannelID: String? { get }
    var selectedChannel: AuthorizedChannel? { get }
    var authorizedChannels: [AuthorizedChannel] { get }
    var selectedPlaylistID: String? { get }
    var oauthConfig: OAuthClientConfig { get }
    var startsUploadsAutomatically: Bool { get }
    var keepMacAwake: Bool { get }
    var hasAcceptedRequiredPolicies: Bool { get }
    var maxConcurrentUploads: Int { get }

    func selectedPlaylistID(for channelID: String) -> String?
    func playlist(id: String, channelID: String) -> YouTubePlaylist?
    func updateCredentials(_ credentials: OAuthCredentials, for channelID: String)
}

extension PreferencesStore: UploadPreferencesProviding {}

typealias AssembleUploadFile = (
    _ sourceURLs: [URL],
    _ titleSeed: String,
    _ onProgress: @escaping (Double) -> Void
) async throws -> URL

typealias UploadVideoFile = (
    _ fileURL: URL,
    _ metadata: UploadMetadata,
    _ channel: AuthorizedChannel,
    _ playlistID: String?,
    _ oauthConfig: OAuthClientConfig,
    _ resumeSessionURL: URL?,
    _ onSessionEstablished: @escaping (URL) -> Void,
    _ onProgress: @escaping (Double) -> Void,
    _ onCredentialsRefreshed: @escaping (OAuthCredentials) -> Void
) async throws -> YouTubeUploadResult

@MainActor
protocol UploadActivityControlling: AnyObject {
    func begin(keepMacAwake: Bool)
    func end()
}

extension BackgroundActivityController: UploadActivityControlling {}

@MainActor
final class UploadStore: ObservableObject {
    @Published private(set) var jobs: [UploadJob] = [] {
        didSet { persistence.scheduleSave(jobs) }
    }
    @Published var errorMessage: String?
    /// True after a launch that restored uploads which were mid-flight when
    /// the app last quit; drives the "Resume interrupted uploads" banner.
    @Published private(set) var showsInterruptedUploadsPrompt = false

    private let preferences: any UploadPreferencesProviding
    private let resolver = VideoChunkResolver()
    private let selector: FileSelectionService
    private let assembleUploadFile: AssembleUploadFile
    private let uploadVideoFile: UploadVideoFile
    private let activity: any UploadActivityControlling
    private let persistence: any UploadQueuePersisting
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingRestartJobIDs = Set<UUID>()
    private var securityScopedURLsByJobID: [UUID: [URL]] = [:]

    init(
        preferences: any UploadPreferencesProviding,
        selector: FileSelectionService? = nil,
        assembleUploadFile: @escaping AssembleUploadFile = { sourceURLs, titleSeed, onProgress in
            try await ChunkAssembler().assembleIfNeeded(
                sourceURLs: sourceURLs,
                titleSeed: titleSeed,
                onProgress: onProgress
            )
        },
        uploadVideoFile: @escaping UploadVideoFile = { fileURL, metadata, channel, playlistID, oauthConfig, resumeSessionURL, onSessionEstablished, onProgress, onCredentialsRefreshed in
            try await YouTubeUploadService().upload(
                fileURL: fileURL,
                metadata: metadata,
                channel: channel,
                playlistID: playlistID,
                oauthConfig: oauthConfig,
                resumeSessionURL: resumeSessionURL,
                onSessionEstablished: onSessionEstablished,
                onProgress: onProgress,
                onCredentialsRefreshed: onCredentialsRefreshed
            )
        },
        activity: (any UploadActivityControlling)? = nil,
        persistence: (any UploadQueuePersisting)? = nil
    ) {
        self.preferences = preferences
        self.selector = selector ?? FileSelectionService()
        self.assembleUploadFile = assembleUploadFile
        self.uploadVideoFile = uploadVideoFile
        self.activity = activity ?? BackgroundActivityController()
        self.persistence = persistence ?? Self.makeDefaultPersistence()
        restorePersistedJobs()
    }

    /// Hosted unit tests run the app's launch path, so the default store the
    /// app creates must not read or overwrite the user's real queue file.
    private static func makeDefaultPersistence() -> any UploadQueuePersisting {
        guard NSClassFromString("XCTestCase") == nil else {
            return InMemoryUploadQueuePersistence()
        }
        return UploadQueuePersistence()
    }

    private func restorePersistedJobs() {
        let loaded = persistence.loadJobs()
        guard !loaded.isEmpty else { return }

        var restored: [UploadJob] = []
        for job in loaded {
            var job = job
            var accessedURLs: [URL] = []

            for index in job.sourceBookmarks.indices {
                guard let bookmark = job.sourceBookmarks[index],
                      let resolution = SecurityScopedBookmark.resolveAndStartAccessing(bookmark) else {
                    continue
                }
                if resolution.didStartAccessing {
                    accessedURLs.append(resolution.url)
                }
                if index < job.sourceURLs.count {
                    job.sourceURLs[index] = resolution.url
                }
                if let refreshedBookmark = resolution.refreshedBookmark {
                    job.sourceBookmarks[index] = refreshedBookmark
                }
            }

            if job.phase == .interrupted {
                job.detail = "Interrupted by quit. Resume to continue."
            }

            if !accessedURLs.isEmpty {
                securityScopedURLsByJobID[job.id] = accessedURLs
            }
            restored.append(job)
        }

        jobs = restored
        showsInterruptedUploadsPrompt = restored.contains { $0.phase == .interrupted }
    }

    private func stopSecurityScopedAccess(for jobID: UUID) {
        guard let urls = securityScopedURLsByJobID.removeValue(forKey: jobID) else { return }
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var activeCount: Int {
        activeJobs.count
    }

    var queuedCount: Int {
        jobs.filter { $0.phase == .queued }.count
    }

    var completedCount: Int {
        jobs.filter {
            if case .completed = $0.phase { return true }
            return false
        }.count
    }

    var failedCount: Int {
        jobs.filter {
            if case .failed = $0.phase { return true }
            return false
        }.count
    }

    var interruptedCount: Int {
        jobs.filter { $0.phase == .interrupted }.count
    }

    var cancellableCount: Int {
        jobs.filter(\.phase.canCancel).count
    }

    var uploadActivityStatus: UploadActivityStatus? {
        let uploadingJobs = activeJobs.filter { $0.phase == .uploading }
        guard let primaryJob = uploadingJobs.first ?? activeJobs.first else { return nil }

        let progressJobs = uploadingJobs.isEmpty ? activeJobs : uploadingJobs
        let progressTotal = progressJobs.reduce(0) { partial, job in
            partial + job.progress
        }
        let averageProgress = progressTotal / Double(progressJobs.count)

        return UploadActivityStatus(
            title: primaryJob.metadata.title,
            detail: primaryJob.detail,
            progress: min(max(averageProgress, 0), 1),
            activeCount: activeJobs.count,
            uploadingCount: uploadingJobs.count,
            queuedCount: queuedCount
        )
    }

    private var activeJobs: [UploadJob] {
        jobs.filter { $0.phase.isActive }
    }

    func chooseAndEnqueueFiles() {
        let urls = selector.chooseVideos()
        enqueue(urls)
    }

    func enqueue(_ urls: [URL]) {
        let groups = resolver.resolve(urls: urls)
        guard !groups.isEmpty else { return }

        let channelID = preferences.selectedChannelID
        let newJobs = groups.map { group in
            UploadJob(
                sourceURLs: group.sourceURLs,
                titleSeed: group.titleSeed,
                metadata: preferences.metadata.uploadMetadata(for: group.titleSeed),
                selectedChannelID: channelID,
                selectedPlaylistID: channelID.flatMap { preferences.selectedPlaylistID(for: $0) }
            )
        }

        jobs.append(contentsOf: newJobs)
        if preferences.startsUploadsAutomatically {
            startQueuedUploads()
        }
    }

    func startQueuedUploads() {
        errorMessage = nil

        guard preferences.hasAcceptedRequiredPolicies else {
            errorMessage = AppError.legalAgreementRequired.localizedDescription
            return
        }

        guard preferences.selectedChannel != nil else {
            for index in jobs.indices where jobs[index].phase.startsWhenQueueStarts {
                jobs[index].phase = .waitingForAccount
                jobs[index].detail = "Connect a YouTube channel to start."
            }
            showsInterruptedUploadsPrompt = false
            return
        }

        prepareStartableJobs()
        showsInterruptedUploadsPrompt = false

        let inFlightRetryIDs = jobs
            .filter { $0.phase == .queued && runningTasks[$0.id] != nil }
            .map(\.id)
        pendingRestartJobIDs.formUnion(inFlightRetryIDs)

        startNextQueuedUploadsWithinLimit()
    }

    /// Resumes only the uploads that were interrupted by the last quit or
    /// crash, leaving failed and waiting jobs alone. Same gates as
    /// `startQueuedUploads`: legal consent, a connected channel, and the
    /// concurrent-upload limit.
    func resumeInterruptedUploads() {
        errorMessage = nil

        guard preferences.hasAcceptedRequiredPolicies else {
            errorMessage = AppError.legalAgreementRequired.localizedDescription
            return
        }

        guard preferences.selectedChannel != nil else {
            for index in jobs.indices where jobs[index].phase == .interrupted {
                jobs[index].phase = .waitingForAccount
                jobs[index].detail = "Connect a YouTube channel to start."
            }
            showsInterruptedUploadsPrompt = false
            return
        }

        for index in jobs.indices where jobs[index].phase == .interrupted {
            prepareJobForStart(at: index)
        }
        showsInterruptedUploadsPrompt = false

        startNextQueuedUploadsWithinLimit()
    }

    func dismissInterruptedUploadsPrompt() {
        showsInterruptedUploadsPrompt = false
    }

    private func startNextQueuedUploadsWithinLimit() {
        let limit = max(1, preferences.maxConcurrentUploads)
        let availableSlots = limit - runningTasks.count
        guard availableSlots > 0 else { return }

        let startableIDs = jobs
            .filter { $0.phase == .queued && runningTasks[$0.id] == nil }
            .prefix(availableSlots)
            .map(\.id)

        guard !startableIDs.isEmpty else { return }

        activity.begin(keepMacAwake: preferences.keepMacAwake)
        for id in startableIDs {
            runningTasks[id] = Task { await process(jobID: id) }
        }
    }

    func updateJob(
        id jobID: UUID,
        metadata: UploadMetadata,
        selectedChannelID: String?,
        selectedPlaylistID: String?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].phase.canEditBeforeUpload else {
            return
        }

        jobs[index].metadata = metadata
        jobs[index].selectedChannelID = selectedChannelID
        jobs[index].selectedPlaylistID = selectedChannelID.flatMap { channelID in
            if let selectedPlaylistID,
               preferences.playlist(id: selectedPlaylistID, channelID: channelID) != nil {
                return selectedPlaylistID
            }
            return nil
        }

        if selectedChannelID == nil {
            jobs[index].phase = .waitingForAccount
            jobs[index].detail = "Connect a YouTube channel to start."
        } else if jobs[index].phase == .waitingForAccount {
            jobs[index].phase = .queued
            jobs[index].detail = "Ready"
        }
    }

    func cancel(jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              jobs[index].phase.canCancel else {
            return
        }

        if let task = runningTasks[jobID] {
            jobs[index].detail = "Cancelling..."
            task.cancel()
        } else {
            jobs[index].phase = .cancelled
            jobs[index].progress = 0
            jobs[index].detail = "Cancelled"
            jobs[index].resumableSessionURL = nil
            jobs[index].resumableFileSize = nil
            pendingRestartJobIDs.remove(jobID)
        }
    }

    func cancelAllCancellableJobs() {
        for jobID in jobs.filter(\.phase.canCancel).map(\.id) {
            cancel(jobID: jobID)
        }
    }

    func clearFinishedJobs() {
        for job in jobs where job.phase.isTerminal {
            if let assembledFileURL = reusableAssembledFileURL(for: job) {
                removeTemporaryAssembly(for: assembledFileURL, originalSources: job.sourceURLs)
            }
            stopSecurityScopedAccess(for: job.id)
        }
        jobs.removeAll { $0.phase.isTerminal }
    }

    func clearError() {
        errorMessage = nil
    }

    private func process(jobID: UUID) async {
        defer {
            let shouldRestart = pendingRestartJobIDs.remove(jobID) != nil
            runningTasks[jobID] = nil
            if shouldRestart {
                startQueuedUploads()
            } else {
                startNextQueuedUploadsWithinLimit()
            }
            if runningTasks.isEmpty {
                activity.end()
            }
        }

        guard let initialIndex = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        guard let selectedChannelID = jobs[initialIndex].selectedChannelID ?? preferences.selectedChannelID,
              let channel = preferences.authorizedChannels.first(where: { $0.id == selectedChannelID }) else {
            update(jobID) { job in
                job.phase = .waitingForAccount
                job.detail = "Connect a YouTube channel to start."
            }
            return
        }
        let selectedPlaylistID = jobs[initialIndex].selectedPlaylistID ?? preferences.selectedPlaylistID(for: selectedChannelID)
        let selectedPlaylist = selectedPlaylistID.flatMap {
            preferences.playlist(id: $0, channelID: selectedChannelID)
        }

        do {
            update(jobID) { job in
                job.phase = .preparing
                job.progress = 0
                job.detail = "Preparing files"
            }

            guard let snapshot = jobs.first(where: { $0.id == jobID }) else { return }

            let uploadURL = try await preparedUploadURL(for: snapshot, jobID: jobID)

            update(jobID) { job in
                job.assembledFileURL = uploadURL
                job.phase = .uploading
                job.progress = 0
                job.detail = uploadDetail(channelTitle: channel.title, playlistTitle: selectedPlaylist?.title)
            }

            let result = try await uploadVideoFile(
                uploadURL,
                snapshot.metadata,
                channel,
                selectedPlaylistID,
                preferences.oauthConfig,
                resumeSessionURL(for: snapshot, uploadURL: uploadURL),
                { [weak self] sessionURL in
                    let uploadFileSize = uploadURL.fileSize
                    Task { @MainActor in
                        self?.update(jobID) { job in
                            job.resumableSessionURL = sessionURL
                            job.resumableFileSize = uploadFileSize
                        }
                    }
                },
                { [weak self] progress in
                    Task { @MainActor in
                        self?.update(jobID) { job in
                            job.progress = progress
                            job.detail = "\(Int(progress * 100))% uploaded"
                        }
                    }
                },
                { [weak self] credentials in
                    Task { @MainActor in
                        self?.preferences.updateCredentials(credentials, for: channel.id)
                    }
                }
            )

            update(jobID) { job in
                job.phase = .completed(videoID: result.videoID)
                job.progress = 1
                job.detail = completionDetail(
                    for: job,
                    result: result,
                    playlistTitle: selectedPlaylist?.title
                )
                job.resumableSessionURL = nil
                job.resumableFileSize = nil
            }
            if let playlistErrorDescription = result.playlistErrorDescription {
                let playlistName = selectedPlaylist?.title ?? "the selected playlist"
                errorMessage = "Uploaded \(snapshot.metadata.title), but could not add it to \(playlistName): \(playlistErrorDescription)"
            }

            removeTemporaryAssembly(for: uploadURL, originalSources: snapshot.sourceURLs)
        } catch is CancellationError {
            cancelActiveJob(jobID)
        } catch {
            if error.isCancellation {
                cancelActiveJob(jobID)
                return
            }
            update(jobID) { job in
                job.phase = .failed(error.localizedDescription)
                job.detail = error.localizedDescription
                // The service cancels the resumable session on the way out of
                // an in-run failure, so the stored URL is no longer usable.
                job.resumableSessionURL = nil
                job.resumableFileSize = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    /// A stored session is only offered for resume when it was opened for the
    /// exact bytes about to be uploaded: the file size must match what was
    /// recorded, and multi-chunk jobs must still have the original assembled
    /// file (a re-assembled file is not guaranteed byte-identical).
    private func resumeSessionURL(for snapshot: UploadJob, uploadURL: URL) -> URL? {
        guard let sessionURL = snapshot.resumableSessionURL,
              let recordedFileSize = snapshot.resumableFileSize,
              uploadURL.fileSize == recordedFileSize else {
            return nil
        }
        if snapshot.chunkCount > 1, snapshot.assembledFileURL != uploadURL {
            return nil
        }
        return sessionURL
    }

    private func update(_ jobID: UUID, mutate: (inout UploadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }
        mutate(&jobs[index])
    }

    private func cancelActiveJob(_ jobID: UUID) {
        update(jobID) { job in
            job.phase = .cancelled
            job.detail = "Cancelled"
            job.resumableSessionURL = nil
            job.resumableFileSize = nil
        }
    }

    private func prepareStartableJobs() {
        for index in jobs.indices where jobs[index].phase.startsWhenQueueStarts {
            prepareJobForStart(at: index)
        }
    }

    private func prepareJobForStart(at index: Int) {
        let wasWaitingForAccount = jobs[index].phase == .waitingForAccount
        let wasInterrupted = jobs[index].phase == .interrupted
        let wasFailed: Bool
        if case .failed = jobs[index].phase {
            wasFailed = true
        } else {
            wasFailed = false
        }

        if wasWaitingForAccount || jobs[index].selectedChannelID == nil {
            jobs[index].selectedChannelID = preferences.selectedChannelID
            jobs[index].selectedPlaylistID = preferences.selectedPlaylistID
        }

        if wasFailed || wasInterrupted,
           jobs[index].assembledFileURL != nil,
           reusableAssembledFileURL(for: jobs[index]) == nil {
            jobs[index].assembledFileURL = nil
        }

        jobs[index].phase = .queued
        jobs[index].progress = 0
        jobs[index].detail = readyDetail(
            for: jobs[index],
            wasFailed: wasFailed,
            wasInterrupted: wasInterrupted
        )
    }

    private func readyDetail(for job: UploadJob, wasFailed: Bool, wasInterrupted: Bool) -> String {
        if wasInterrupted {
            return job.resumableSessionURL != nil ? "Ready to resume" : "Ready to restart"
        }
        guard wasFailed else { return "Ready" }
        if reusableAssembledFileURL(for: job) != nil {
            return "Ready to retry reconstructed file"
        }
        return "Ready to retry"
    }

    private func preparedUploadURL(for snapshot: UploadJob, jobID: UUID) async throws -> URL {
        if let assembledFileURL = reusableAssembledFileURL(for: snapshot) {
            update(jobID) { job in
                job.phase = .preparing
                job.progress = 0
                job.detail = "Using reconstructed file"
            }
            return assembledFileURL
        }

        update(jobID) { job in
            job.phase = snapshot.chunkCount > 1 ? .reconstructing : .preparing
            job.progress = 0
            job.detail = snapshot.chunkCount > 1
                ? "Reconstructing \(snapshot.chunkCount) chunks"
                : "Preparing \(snapshot.sourceURLs.first?.lastPathComponent ?? "video")"
        }

        return try await assembleUploadFile(
            snapshot.sourceURLs,
            snapshot.titleSeed,
            { [weak self] progress in
                let clampedProgress = min(max(progress, 0), 1)
                Task { @MainActor in
                    self?.update(jobID) { job in
                        guard case .reconstructing = job.phase else { return }
                        job.progress = clampedProgress
                        job.detail = "Remuxing \(snapshot.chunkCount) chunks (\(Int((clampedProgress * 100).rounded()))%)"
                    }
                }
            }
        )
    }

    private func uploadDetail(channelTitle: String, playlistTitle: String?) -> String {
        guard let playlistTitle else {
            return "Uploading to \(channelTitle)"
        }
        return "Uploading to \(channelTitle), then adding to \(playlistTitle)"
    }

    private func completionDetail(
        for job: UploadJob,
        result: YouTubeUploadResult,
        playlistTitle: String?
    ) -> String {
        let publishedDetail = job.publishedDetail ?? "Uploaded"

        if let playlistErrorDescription = result.playlistErrorDescription {
            return "\(publishedDetail). Playlist not updated: \(playlistErrorDescription)"
        }

        guard result.wasAddedToPlaylist, let playlistTitle else {
            return publishedDetail
        }

        return "\(publishedDetail) and added to \(playlistTitle)"
    }

    private func removeTemporaryAssembly(for uploadURL: URL, originalSources: [URL]) {
        guard isTemporaryAssembly(uploadURL, originalSources: originalSources) else {
            return
        }
        try? FileManager.default.removeItem(at: uploadURL)
    }

    private func reusableAssembledFileURL(for job: UploadJob) -> URL? {
        guard job.chunkCount > 1,
              let assembledFileURL = job.assembledFileURL,
              isTemporaryAssembly(assembledFileURL, originalSources: job.sourceURLs),
              FileManager.default.fileExists(atPath: assembledFileURL.path),
              (assembledFileURL.fileSize ?? 0) > 0 else {
            return nil
        }

        return assembledFileURL
    }

    private func isTemporaryAssembly(_ url: URL, originalSources: [URL]) -> Bool {
        guard !originalSources.contains(url) else {
            return false
        }

        let assemblyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacYouTubeUploader", isDirectory: true)
            .standardizedFileURL
            .path
        let assemblyPath = url.standardizedFileURL.path

        return assemblyPath.hasPrefix(assemblyDirectory + "/")
    }
}

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }
        return (self as? URLError)?.code == .cancelled
    }
}
