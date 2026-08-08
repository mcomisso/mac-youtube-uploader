import AVFoundation
import AppKit
import Foundation

actor VideoThumbnailGenerator {
    private var cache: [ThumbnailCacheKey: NSImage] = [:]

    func thumbnail(for urls: [URL], maximumSize: CGSize) async -> NSImage? {
        for url in urls {
            if let image = thumbnail(for: url, maximumSize: maximumSize) {
                return image
            }
        }
        return nil
    }

    private func thumbnail(for url: URL, maximumSize: CGSize) -> NSImage? {
        let key = ThumbnailCacheKey(url: url, maximumSize: maximumSize)
        if let image = cache[key] {
            return image
        }

        guard let image = Self.makeThumbnail(for: url, maximumSize: maximumSize) else {
            return nil
        }

        cache[key] = image
        return image
    }

    private static func makeThumbnail(for url: URL, maximumSize: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)

        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        for time in [1.0, 0.25, 0.0].map({ CMTime(seconds: $0, preferredTimescale: 600) }) {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(
                    cgImage: cgImage,
                    size: CGSize(width: cgImage.width, height: cgImage.height)
                )
            }
        }

        return nil
    }
}

nonisolated private struct ThumbnailCacheKey: Hashable, Sendable {
    var path: String
    var fileSize: Int64?
    var modifiedAt: Date?
    var width: Int
    var height: Int

    init(url: URL, maximumSize: CGSize) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        self.path = url.standardizedFileURL.path
        self.fileSize = values?.fileSize.map(Int64.init)
        self.modifiedAt = values?.contentModificationDate
        self.width = Int(maximumSize.width.rounded())
        self.height = Int(maximumSize.height.rounded())
    }
}
