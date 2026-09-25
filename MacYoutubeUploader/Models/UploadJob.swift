import Foundation

enum UploadPhase: Equatable {
    case queued
    case waitingForAccount
    case preparing
    case reconstructing
    case uploading
    case interrupted
    case completed(videoID: String?)
    case failed(String)
    case cancelled

    var label: String {
        switch self {
        case .queued: "Queued"
        case .waitingForAccount: "Connect account"
        case .preparing: "Preparing"
        case .reconstructing: "Reconstructing"
        case .uploading: "Uploading"
        case .interrupted: "Interrupted"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var isTerminal: Bool {
        if case .completed = self { return true }
        if case .failed = self { return true }
        if case .cancelled = self { return true }
        return false
    }

    var isActive: Bool {
        switch self {
        case .preparing, .reconstructing, .uploading:
            return true
        default:
            return false
        }
    }

    var startsWhenQueueStarts: Bool {
        switch self {
        case .queued, .waitingForAccount, .failed, .interrupted:
            return true
        default:
            return false
        }
    }

    var canCancel: Bool {
        switch self {
        case .queued, .waitingForAccount, .preparing, .reconstructing, .uploading, .interrupted:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    var canEditBeforeUpload: Bool {
        switch self {
        case .queued, .waitingForAccount, .failed, .interrupted:
            return true
        case .preparing, .reconstructing, .uploading, .completed, .cancelled:
            return false
        }
    }

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }

    var publishedVideoID: String? {
        guard case let .completed(videoID) = self else { return nil }
        return videoID
    }
}

extension UploadPhase: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case videoID
        case message
    }

    /// Phases that only make sense inside a running process (.preparing,
    /// .reconstructing, .uploading) are persisted as `interrupted` so a
    /// restored queue can offer to resume them instead of pretending the
    /// work is still in flight.
    private enum Kind: String, Codable {
        case queued
        case waitingForAccount
        case interrupted
        case completed
        case failed
        case cancelled
    }

    private var persistedKind: Kind {
        switch self {
        case .queued: .queued
        case .waitingForAccount: .waitingForAccount
        case .preparing, .reconstructing, .uploading, .interrupted: .interrupted
        case .completed: .completed
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .queued:
            self = .queued
        case .waitingForAccount:
            self = .waitingForAccount
        case .interrupted:
            self = .interrupted
        case .completed:
            self = .completed(videoID: try container.decodeIfPresent(String.self, forKey: .videoID))
        case .failed:
            self = .failed(try container.decodeIfPresent(String.self, forKey: .message) ?? "Upload failed")
        case .cancelled:
            self = .cancelled
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(persistedKind, forKey: .kind)
        if case let .completed(videoID) = self {
            try container.encodeIfPresent(videoID, forKey: .videoID)
        }
        if case let .failed(message) = self {
            try container.encode(message, forKey: .message)
        }
    }
}

struct UploadJob: Identifiable, Equatable {
    let id: UUID
    var sourceURLs: [URL]
    /// Security-scoped bookmarks aligned with `sourceURLs`, so user-selected
    /// files stay readable after a relaunch under App Sandbox. `nil` entries
    /// mean bookmark creation failed for that source.
    var sourceBookmarks: [Data?]
    var titleSeed: String
    var metadata: UploadMetadata
    var phase: UploadPhase
    var progress: Double
    var detail: String
    var createdAt: Date
    var selectedChannelID: String?
    var selectedPlaylistID: String?
    var assembledFileURL: URL?
    /// The Google resumable session URL for an in-flight upload, kept so an
    /// interrupted upload can resume from the server-reported offset after a
    /// relaunch. Only valid for the exact file it was opened for, recorded
    /// via `resumableFileSize`.
    var resumableSessionURL: URL?
    var resumableFileSize: Int64?

    init(
        sourceURLs: [URL],
        titleSeed: String,
        metadata: UploadMetadata,
        selectedChannelID: String?,
        selectedPlaylistID: String?
    ) {
        self.id = UUID()
        self.sourceURLs = sourceURLs
        self.sourceBookmarks = sourceURLs.map(SecurityScopedBookmark.bookmarkData(for:))
        self.titleSeed = titleSeed
        self.metadata = metadata
        self.phase = selectedChannelID == nil ? .waitingForAccount : .queued
        self.progress = 0
        self.detail = sourceURLs.count > 1
            ? "\(sourceURLs.count) files selected"
            : sourceURLs.first?.lastPathComponent ?? "Ready"
        self.createdAt = Date()
        self.selectedChannelID = selectedChannelID
        self.selectedPlaylistID = selectedPlaylistID
        self.assembledFileURL = nil
        self.resumableSessionURL = nil
        self.resumableFileSize = nil
    }

    var chunkCount: Int {
        sourceURLs.count
    }

    var totalBytes: Int64 {
        sourceURLs.reduce(Int64(0)) { partial, url in
            partial + (url.fileSize ?? 0)
        }
    }

    var totalSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var publishedVideoURL: URL? {
        guard let videoID = phase.publishedVideoID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !videoID.isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url
    }

    var publishedDetail: String? {
        publishedVideoURL.map { "Published as \($0.absoluteString)" }
    }
}

extension UploadJob: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case sourceURLs
        case sourceBookmarks
        case titleSeed
        case metadata
        case phase
        case progress
        case detail
        case createdAt
        case selectedChannelID
        case selectedPlaylistID
        case assembledFileURL
        case resumableSessionURL
        case resumableFileSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sourceURLs = try container.decode([URL].self, forKey: .sourceURLs)
        self.sourceBookmarks = try container.decodeIfPresent([Data?].self, forKey: .sourceBookmarks)
            ?? Array(repeating: nil, count: sourceURLs.count)
        self.titleSeed = try container.decode(String.self, forKey: .titleSeed)
        self.metadata = try container.decode(UploadMetadata.self, forKey: .metadata)
        self.phase = try container.decode(UploadPhase.self, forKey: .phase)
        self.progress = try container.decode(Double.self, forKey: .progress)
        self.detail = try container.decode(String.self, forKey: .detail)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.selectedChannelID = try container.decodeIfPresent(String.self, forKey: .selectedChannelID)
        self.selectedPlaylistID = try container.decodeIfPresent(String.self, forKey: .selectedPlaylistID)
        self.assembledFileURL = try container.decodeIfPresent(URL.self, forKey: .assembledFileURL)
        self.resumableSessionURL = try container.decodeIfPresent(URL.self, forKey: .resumableSessionURL)
        self.resumableFileSize = try container.decodeIfPresent(Int64.self, forKey: .resumableFileSize)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceURLs, forKey: .sourceURLs)
        try container.encode(sourceBookmarks, forKey: .sourceBookmarks)
        try container.encode(titleSeed, forKey: .titleSeed)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(phase, forKey: .phase)
        try container.encode(progress, forKey: .progress)
        try container.encode(detail, forKey: .detail)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(selectedChannelID, forKey: .selectedChannelID)
        try container.encodeIfPresent(selectedPlaylistID, forKey: .selectedPlaylistID)
        try container.encodeIfPresent(assembledFileURL, forKey: .assembledFileURL)
        try container.encodeIfPresent(resumableSessionURL, forKey: .resumableSessionURL)
        try container.encodeIfPresent(resumableFileSize, forKey: .resumableFileSize)
    }
}

struct ResolvedUploadGroup: Equatable {
    var sourceURLs: [URL]
    var titleSeed: String
}

struct UploadActivityStatus: Equatable {
    var title: String
    var detail: String
    var progress: Double
    var activeCount: Int
    var uploadingCount: Int
    var queuedCount: Int

    var isUploading: Bool {
        uploadingCount > 0
    }

    var percentUploaded: Int {
        Int((progress * 100).rounded())
    }

    var shortTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedTitle.isEmpty ? "Upload" : trimmedTitle
        guard displayTitle.count > 30 else { return displayTitle }
        return String(displayTitle.prefix(27)) + "..."
    }
}
