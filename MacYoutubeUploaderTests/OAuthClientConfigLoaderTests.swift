import XCTest
@testable import MacYoutubeUploader

final class OAuthClientConfigLoaderTests: XCTestCase {
    func testBuiltTestHostContainsUsableBundledGoogleOAuthDesktopClientID() throws {
        let clientID = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "YouTubeOAuthClientID") as? String,
            "The built app must bundle a Google OAuth desktop client ID so Sign in with Google can open."
        )
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertFalse(
            normalizedClientID.isEmpty,
            "The built app must bundle a non-empty Google OAuth desktop client ID."
        )
        XCTAssertFalse(
            normalizedClientID.hasPrefix("$("),
            "The bundled Google OAuth desktop client ID must not be an unresolved build-setting placeholder."
        )
        XCTAssertTrue(
            normalizedClientID.hasSuffix(".apps.googleusercontent.com"),
            "The bundled OAuth client ID must be a Google client ID ending in .apps.googleusercontent.com."
        )
    }

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
