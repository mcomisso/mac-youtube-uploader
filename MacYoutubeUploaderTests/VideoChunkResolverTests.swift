import XCTest
@testable import MacYoutubeUploader

final class VideoChunkResolverTests: XCTestCase {
    func testGroupsSequentialCameraSuffixes() {
        let root = URL(fileURLWithPath: "/tmp/camera")
        let urls = [
            root.appendingPathComponent("A001_070121_0001.MP4"),
            root.appendingPathComponent("A001_070121_0002.MP4"),
            root.appendingPathComponent("A001_070121_0003.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "A001_070121")
    }

    func testGroupsGoProChapterFilesByClipID() {
        let root = URL(fileURLWithPath: "/tmp/gopro")
        let urls = [
            root.appendingPathComponent("GX010123.MP4"),
            root.appendingPathComponent("GX020123.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "GX0123")
    }

    func testGroupsLegacyGoProChapterFilesByClipID() {
        let root = URL(fileURLWithPath: "/tmp/gopro")
        let urls = [
            root.appendingPathComponent("GOPR1234.MP4"),
            root.appendingPathComponent("GP011234.MP4"),
            root.appendingPathComponent("GP021234.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "GOPR1234")
    }

    func testGroupsGoProChapterFilesWithCustomBasename() {
        let root = URL(fileURLWithPath: "/tmp/gopro")
        let urls = [
            root.appendingPathComponent("Ride-GH013607.MP4"),
            root.appendingPathComponent("Ride-GH023607.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "Ride-GH3607")
    }

    func testGroupsSequentialDJIFilesWithCloseFilenameTimestamps() {
        let root = URL(fileURLWithPath: "/tmp/dji")
        let urls = [
            root.appendingPathComponent("DJI_20260418154811_0008_D.MP4"),
            root.appendingPathComponent("DJI_20260418154911_0009_D.MP4"),
            root.appendingPathComponent("DJI_20260418155011_0010_D.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "DJI_20260418154811_D")
    }

    func testGroupsLargeSequentialDJIChunksAcrossLongerFilenameTimestampGap() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoChunkResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let urls = [
            root.appendingPathComponent("DJI_20260418154811_0008_D.MP4"),
            root.appendingPathComponent("DJI_20260418165011_0009_D.MP4")
        ]
        try makeSparseVideo(at: urls[0], byteCount: 4_100_000_000)
        try makeSparseVideo(at: urls[1], byteCount: 100_000_000)

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.sourceURLs, urls)
        XCTAssertEqual(groups.first?.titleSeed, "DJI_20260418154811_D")
    }

    func testSplitsSequentialDJIFilesWhenFilenameTimestampsAreFarApart() {
        let root = URL(fileURLWithPath: "/tmp/dji")
        let urls = [
            root.appendingPathComponent("DJI_20260418154811_0008_D.MP4"),
            root.appendingPathComponent("DJI_20260418171031_0009_D.MP4"),
            root.appendingPathComponent("DJI_20260418183544_0010_D.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map(\.sourceURLs), urls.map { [$0] })
        XCTAssertEqual(groups.map(\.titleSeed), [
            "DJI_20260418154811_D",
            "DJI_20260418171031_D",
            "DJI_20260418183544_D"
        ])
    }

    func testLeavesUnmatchedFilesSeparate() {
        let root = URL(fileURLWithPath: "/tmp/singles")
        let urls = [
            root.appendingPathComponent("interview.MP4"),
            root.appendingPathComponent("broll.MP4")
        ]

        let groups = VideoChunkResolver().resolve(urls: urls)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.sourceURLs.count), [1, 1])
    }
}

private func makeSparseVideo(at url: URL, byteCount: UInt64) throws {
    _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: byteCount)
    try handle.close()
}

final class UploadJobTests: XCTestCase {
    func testPublishedVideoURLUsesYouTubeWatchURL() {
        var job = UploadJob(
            sourceURLs: [URL(fileURLWithPath: "/tmp/video.mp4")],
            titleSeed: "video",
            metadata: UploadMetadata(
                title: "video",
                description: "",
                tags: [],
                categoryID: "22",
                privacy: .private,
                madeForKids: false,
                allowEmbedding: true
            ),
            selectedChannelID: "channel",
            selectedPlaylistID: nil
        )

        job.phase = .completed(videoID: "abc123")

        XCTAssertEqual(job.publishedVideoURL?.absoluteString, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(job.publishedDetail, "Published as https://www.youtube.com/watch?v=abc123")
    }
}
