import Foundation

enum QueueFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case uploading
    case queued
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Uploads"
        case .uploading: "Uploading"
        case .queued: "Queued"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .uploading: "arrow.up.circle"
        case .queued: "clock"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    func matches(_ job: UploadJob) -> Bool {
        switch self {
        case .all:
            return true
        case .uploading:
            return job.phase.isActive
        case .queued:
            return job.phase == .queued || job.phase == .waitingForAccount || job.phase == .interrupted
        case .completed:
            if case .completed = job.phase { return true }
            return false
        case .failed:
            if case .failed = job.phase { return true }
            return false
        }
    }

    func count(in jobs: [UploadJob]) -> Int {
        jobs.filter(matches).count
    }
}
