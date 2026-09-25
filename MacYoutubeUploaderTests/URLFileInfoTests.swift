import XCTest
@testable import MacYoutubeUploader

final class URLFileInfoTests: XCTestCase {
    func testMOVIsRecognizedWhenSystemTypeLookupIsUnavailable() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("MOV")
        try Data([0, 1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(url.isSupportedVideoFile)
        XCTAssertEqual(url.probableVideoMimeType, "video/quicktime")
    }
}
