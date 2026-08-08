import Foundation
import UniformTypeIdentifiers

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
        guard let type = UTType(filenameExtension: pathExtension) else {
            return "video/mp4"
        }
        return type.preferredMIMEType ?? "video/mp4"
    }

    var isSupportedVideoFile: Bool {
        guard !isDirectory else { return false }
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
