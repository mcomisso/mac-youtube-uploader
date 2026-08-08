import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
struct FileSelectionService {
    func chooseVideos() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Videos"
        panel.prompt = "Add to Queue"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie,
            .audiovisualContent
        ]

        return panel.runModal() == .OK ? panel.urls : []
    }
}
