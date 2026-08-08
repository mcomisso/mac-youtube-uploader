import XCTest
@testable import MacYoutubeUploader

final class OAuthClientConfigLoaderTests: XCTestCase {
    func testImportsInstalledClientJSON() throws {
        let url = try makeJSONFile(#"{"installed":{"client_id":"abc.apps.googleusercontent.com","client_secret":"shhh"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try OAuthClientConfigLoader.importConfig(from: url)

        XCTAssertEqual(config.clientID, "abc.apps.googleusercontent.com")
        XCTAssertEqual(config.clientSecret, "shhh")
    }

    func testImportsWebClientJSONWithoutSecret() throws {
        let url = try makeJSONFile(#"{"web":{"client_id":"web-client-id"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        let config = try OAuthClientConfigLoader.importConfig(from: url)

        XCTAssertEqual(config.clientID, "web-client-id")
        XCTAssertEqual(config.clientSecret, "")
    }

    func testThrowsForNonGoogleJSON() throws {
        let url = try makeJSONFile(#"{"something":"else"}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try OAuthClientConfigLoader.importConfig(from: url)) { error in
            XCTAssertEqual(error as? OAuthClientConfigImportError, .invalidFormat)
        }
    }

    func testThrowsForEmptyClientID() throws {
        let url = try makeJSONFile(#"{"installed":{"client_id":"  "}}"#)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try OAuthClientConfigLoader.importConfig(from: url)) { error in
            XCTAssertEqual(error as? OAuthClientConfigImportError, .invalidFormat)
        }
    }

    func testThrowsForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).json")

        XCTAssertThrowsError(try OAuthClientConfigLoader.importConfig(from: url)) { error in
            XCTAssertEqual(error as? OAuthClientConfigImportError, .unreadable)
        }
    }

    private func makeJSONFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try Data(contents.utf8).write(to: url)
        return url
    }
}
