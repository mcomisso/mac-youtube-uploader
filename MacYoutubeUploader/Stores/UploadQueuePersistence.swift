import AppKit
import Foundation

@MainActor
protocol UploadQueuePersisting: AnyObject {
    func loadJobs() -> [UploadJob]
    func scheduleSave(_ jobs: [UploadJob])
    func flush()
}

/// Persists the upload queue as JSON under Application Support. Saves are
/// debounced because the store mutates jobs on every progress tick; the
/// pending snapshot is flushed when the app terminates.
@MainActor
final class UploadQueuePersistence: UploadQueuePersisting {
    private let fileURL: URL
    private let debounceInterval: TimeInterval
    private var pendingJobs: [UploadJob]?
    private var saveTask: Task<Void, Never>?
    private var terminationObserver: (any NSObjectProtocol)?

    init(
        fileURL: URL = UploadQueuePersistence.defaultFileURL(),
        debounceInterval: TimeInterval = 0.5
    ) {
        self.fileURL = fileURL
        self.debounceInterval = debounceInterval

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    nonisolated static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("MacYouTubeUploader", isDirectory: true)
            .appendingPathComponent("UploadQueue.json")
    }

    func loadJobs() -> [UploadJob] {
        guard let data = try? Data(contentsOf: fileURL),
              let jobs = try? JSONDecoder().decode([UploadJob].self, from: data) else {
            return []
        }
        return jobs
    }

    func scheduleSave(_ jobs: [UploadJob]) {
        pendingJobs = jobs

        guard debounceInterval > 0 else {
            flush()
            return
        }

        saveTask?.cancel()
        saveTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil

        guard let jobs = pendingJobs else { return }
        pendingJobs = nil

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(jobs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort: a failed save must never take down
            // an in-flight upload.
        }
    }
}

/// Keeps the queue out of the real Application Support file. Used as the
/// default while unit tests are hosted in the app, and available to tests
/// that don't care about persistence.
@MainActor
final class InMemoryUploadQueuePersistence: UploadQueuePersisting {
    private(set) var savedJobs: [UploadJob] = []

    init() {}

    func loadJobs() -> [UploadJob] {
        []
    }

    func scheduleSave(_ jobs: [UploadJob]) {
        savedJobs = jobs
    }

    func flush() {}
}
