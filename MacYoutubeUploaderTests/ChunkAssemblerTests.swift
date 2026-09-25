import AVFoundation
import XCTest
@testable import MacYoutubeUploader

final class ChunkAssemblerTests: XCTestCase {
    func testCombinesTwoVideosIntoOnePlayableFile() async throws {
        let fixtureDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let first = fixtureDirectory.appendingPathComponent("clip-red.mov")
        let second = fixtureDirectory.appendingPathComponent("clip-blue.mov")

        let output = try await ChunkAssembler().assembleIfNeeded(
            sourceURLs: [first, second],
            titleSeed: "combined"
        )
        defer { try? FileManager.default.removeItem(at: output) }

        XCTAssertNotEqual(output, first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(CMTimeGetSeconds(duration), 2, accuracy: 0.1)
    }
}
