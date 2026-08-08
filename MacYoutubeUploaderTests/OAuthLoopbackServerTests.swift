import XCTest
@testable import MacYoutubeUploader

final class OAuthLoopbackServerTests: XCTestCase {
    func testResolvesOnlyForCallbackWithExpectedState() async throws {
        let server = try OAuthLoopbackServer(expectedState: "expected-state")
        let port = try await server.start()

        let forgedCode = try await get("http://127.0.0.1:\(port)/oauth2redirect?code=forged&state=wrong")
        XCTAssertEqual(forgedCode, 400)

        let forgedError = try await get("http://127.0.0.1:\(port)/oauth2redirect?error=access_denied&state=wrong")
        XCTAssertEqual(forgedError, 400)

        let missingState = try await get("http://127.0.0.1:\(port)/oauth2redirect?error=access_denied")
        XCTAssertEqual(missingState, 400)

        let strayPath = try await get("http://127.0.0.1:\(port)/favicon.ico")
        XCTAssertEqual(strayPath, 404)

        let genuine = try await get("http://127.0.0.1:\(port)/oauth2redirect?code=real-code&state=expected-state")
        XCTAssertEqual(genuine, 200)

        let callback = try await server.waitForCallback()
        XCTAssertEqual(callback.code, "real-code")
        XCTAssertEqual(callback.state, "expected-state")
    }

    func testDeniedCallbackRequiresExpectedState() async throws {
        let server = try OAuthLoopbackServer(expectedState: "expected-state")
        let port = try await server.start()

        let denied = try await get("http://127.0.0.1:\(port)/oauth2redirect?error=access_denied&state=expected-state")
        XCTAssertEqual(denied, 200)

        do {
            _ = try await server.waitForCallback()
            XCTFail("Expected the denied callback to throw")
        } catch AppError.oauthDenied(let reason) {
            XCTAssertEqual(reason, "access_denied")
        }
    }

    private func get(_ urlString: String) async throws -> Int? {
        let url = try XCTUnwrap(URL(string: urlString))
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode
    }
}
