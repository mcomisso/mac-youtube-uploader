import XCTest
@testable import MacYoutubeUploader

final class OAuthCredentialsTests: XCTestCase {
    func testOlderCredentialsDecodeWithoutClientConfig() throws {
        let data = Data(#"{"accessToken":"old","refreshToken":"refresh","tokenType":"Bearer","expiresAt":0}"#.utf8)

        let credentials = try JSONDecoder().decode(OAuthCredentials.self, from: data)

        XCTAssertNil(credentials.clientConfig)
    }

    func testStoredClientSurvivesRoundTripAndOverridesCurrentSettings() throws {
        let originalClient = OAuthClientConfig(clientID: "original", clientSecret: "secret")
        let currentClient = OAuthClientConfig(clientID: "replacement", clientSecret: "")
        let credentials = OAuthCredentials(
            accessToken: "access",
            refreshToken: "refresh",
            tokenType: "Bearer",
            expiresAt: Date(),
            scope: nil,
            clientConfig: originalClient
        )

        let decoded = try JSONDecoder().decode(
            OAuthCredentials.self,
            from: JSONEncoder().encode(credentials)
        )

        XCTAssertEqual(decoded.oauthConfig(fallback: currentClient), originalClient)
    }
}
