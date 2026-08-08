import AVFoundation
import Foundation

actor ChunkAssembler {
    static let assemblyDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacYouTubeUploader", isDirectory: true)

    /// Deletes assembled files left behind by a crash or force-quit. Safe to
    /// call at launch, before any upload references files in this directory.
    /// Files in `referencedFiles` are kept — restored queue jobs may still
    /// need their assembled file to retry or resume without remuxing.
    nonisolated static func removeLeftoverAssemblies(keeping referencedFiles: Set<URL> = []) {
        let fileManager = FileManager.default
        guard let leftovers = try? fileManager.contentsOfDirectory(
            at: assemblyDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let referencedPaths = Set(referencedFiles.map { $0.standardizedFileURL.path })
        for url in leftovers where !referencedPaths.contains(url.standardizedFileURL.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func assembleIfNeeded(
        sourceURLs: [URL],
        titleSeed: String,
        onProgress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard sourceURLs.count > 1 else {
            guard let first = sourceURLs.first else {
                throw AppError.exportFailed("No source files were provided.")
            }
            return first
        }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AppError.exportUnavailable
        }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero

        onProgress(0)

        for url in sourceURLs {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)

            if let assetVideoTrack = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: assetVideoTrack,
                    at: cursor
                )
            }

            if let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first,
               let audioTrack {
                try audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: assetAudioTrack,
                    at: cursor
                )
            }

            cursor = cursor + duration
        }

        let outputDirectory = Self.assemblyDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let outputURL = outputDirectory
            .appendingPathComponent("\(await titleSeed.sanitizedFilenameComponent)-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AppError.exportUnavailable
        }

        exporter.shouldOptimizeForNetworkUse = true

        do {
            try await export(exporter, to: outputURL, as: .mov, onProgress: onProgress)
        } catch {
            // A cancelled or failed export must not leave a partial multi-GB
            // file behind in the assembly directory.
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        onProgress(1)
        return outputURL
    }

    private func export(
        _ exporter: AVAssetExportSession,
        to outputURL: URL,
        as outputFileType: AVFileType,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        nonisolated(unsafe) let exportSession = exporter
        let progressTask = Task {
            for await state in exportSession.states(updateInterval: 0.25) {
                guard !Task.isCancelled else { break }
                if case let .exporting(progress) = state {
                    onProgress(progress.fractionCompleted)
                }
            }
        }

        defer {
            progressTask.cancel()
        }

        try await withTaskCancellationHandler {
            try await exportSession.export(to: outputURL, as: outputFileType)
        } onCancel: {
            exportSession.cancelExport()
        }
    }
}
