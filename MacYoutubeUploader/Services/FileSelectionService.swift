import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct FileSelectionService {
    func chooseVideos() -> [URL] {
        chooseVideos(title: "Choose Videos", prompt: "Add to Queue", message: nil)
    }

    func chooseVideosToCombine() -> [URL] {
        chooseVideos(
            title: "Choose Videos to Combine",
            prompt: "Combine Files",
            message: "Files are combined into one video in filename order."
        )
    }

    private func chooseVideos(title: String, prompt: String, message: String?) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.message = message
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .audiovisualContent
        ] + ["mov", "mp4", "m4v", "avi", "mkv", "webm", "mpeg", "mpg", "mts", "m2ts"]
            .compactMap { UTType(filenameExtension: $0) }

        return panel.runModal() == .OK ? panel.urls : []
    }
}
