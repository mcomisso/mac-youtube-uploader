import Foundation
import UniformTypeIdentifiers

private let videoMIMETypes: [String: String] = [
    "avi": "video/x-msvideo",
    "m2ts": "video/mp2t",
    "m4v": "video/mp4",
    "mkv": "video/x-matroska",
    "mov": "video/quicktime",
    "mp4": "video/mp4",
    "mpeg": "video/mpeg",
    "mpg": "video/mpeg",
    "mts": "video/mp2t",
    "webm": "video/webm"
]

extension URL {
    var fileSize: Int64? {
        guard let values = try? resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return nil
        }
        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }
        if let allocated = values.totalFileAllocatedSize {
            return Int64(allocated)
        }
        return nil
    }

    var bestFileDate: Date {
        let values = try? resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
    }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    var probableVideoMimeType: String {
        if let mimeType = videoMIMETypes[pathExtension.lowercased()] {
            return mimeType
        }
        guard let type = UTType(filenameExtension: pathExtension) else {
            return "application/octet-stream"
        }
        return type.preferredMIMEType ?? "application/octet-stream"
    }

    var isSupportedVideoFile: Bool {
        guard !isDirectory else { return false }
        if videoMIMETypes[pathExtension.lowercased()] != nil {
            return true
        }
        guard let type = UTType(filenameExtension: pathExtension) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent)
    }
}

extension String {
    var sanitizedFilenameComponent: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "upload" : trimmed
    }
}
