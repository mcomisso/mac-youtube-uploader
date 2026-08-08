import Foundation
import Network

struct OAuthCallback {
    var code: String
    var state: String
}

final class OAuthLoopbackServer {
    static let callbackPath = "/oauth2redirect"

    private let listener: NWListener
    private let expectedState: String
    private let queue = DispatchQueue(label: "com.matcom.MacYouTubeUploader.oauth-loopback")
    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<OAuthCallback, Error>?
    private var pendingCallbackResult: Result<OAuthCallback, Error>?
    private var hasResolvedReady = false
    private var hasResolvedCallback = false

    init(expectedState: String) throws {
        self.expectedState = expectedState
        self.listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.readyContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    self?.handle(state)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    func waitForCallback() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingCallbackResult {
                    self.pendingCallbackResult = nil
                    continuation.resume(with: result)
                    return
                }
                self.callbackContinuation = continuation
            }
        }
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard !hasResolvedReady else { return }
            hasResolvedReady = true
            let port = listener.port?.rawValue ?? 0
            readyContinuation?.resume(returning: port)
            readyContinuation = nil
        case .failed(let error):
            resolveReadyIfNeeded(with: error)
            resolveCallbackIfNeeded(with: .failure(error))
        case .cancelled:
            resolveCallbackIfNeeded(with: .failure(AppError.server("The local OAuth callback server stopped before sign-in completed.")))
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }

            guard error == nil,
                  let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                // A broken stray connection must not abort the pending sign-in.
                connection.cancel()
                return
            }

            switch Self.parseCallback(from: firstLine, expectedState: self.expectedState) {
            case .granted(let callback):
                self.respond(html: Self.successHTML, status: "200 OK", connection: connection)
                self.resolveCallbackIfNeeded(with: .success(callback))
                self.listener.cancel()
            case .denied(let reason):
                self.respond(
                    html: Self.failureHTML(message: "Google reported: \(reason)."),
                    status: "200 OK",
                    connection: connection
                )
                self.resolveCallbackIfNeeded(with: .failure(AppError.oauthDenied(reason)))
                self.listener.cancel()
            case .invalidCallback:
                self.respond(
                    html: Self.failureHTML(message: "Google did not return a valid authorization code."),
                    status: "400 Bad Request",
                    connection: connection
                )
                self.resolveCallbackIfNeeded(with: .failure(AppError.server("Invalid OAuth callback.")))
                self.listener.cancel()
            case .unverified:
                // Requests without the expected state value cannot be trusted.
                // Keep waiting for the genuine Google redirect instead of
                // letting a stray local request abort or spoof the sign-in.
                self.respond(
                    html: Self.failureHTML(message: "The sign-in request could not be verified. Return to the app and try again."),
                    status: "400 Bad Request",
                    connection: connection
                )
            case .notFound:
                self.respond(
                    html: Self.failureHTML(message: "Not found."),
                    status: "404 Not Found",
                    connection: connection
                )
            }
        }
    }

    private func respond(html: String, status: String, connection: NWConnection) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func resolveReadyIfNeeded(with error: Error) {
        guard !hasResolvedReady else { return }
        hasResolvedReady = true
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
    }

    private func resolveCallbackIfNeeded(with result: Result<OAuthCallback, Error>) {
        guard !hasResolvedCallback else { return }
        hasResolvedCallback = true

        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            // The redirect can arrive before waitForCallback registers its
            // continuation; keep the result so the waiter is not left hanging.
            pendingCallbackResult = result
        }
    }

    private enum CallbackParseResult {
        case granted(OAuthCallback)
        case denied(String)
        case invalidCallback
        case unverified
        case notFound
    }

    private static func parseCallback(from firstLine: String, expectedState: String) -> CallbackParseResult {
        let pieces = firstLine.split(separator: " ")
        guard pieces.count >= 2,
              let components = URLComponents(string: "http://127.0.0.1\(String(pieces[1]))") else {
            return .notFound
        }

        guard components.path == callbackPath else {
            return .notFound
        }

        let queryItems = components.queryItems ?? []
        guard !expectedState.isEmpty,
              queryItems.first(where: { $0.name == "state" })?.value == expectedState else {
            return .unverified
        }

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            return .denied(error)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .invalidCallback
        }

        return .granted(OAuthCallback(code: code, state: expectedState))
    }

    private static let successHTML = """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"><title>Connected</title></head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 40px;">
        <h1>Connected to YouTube</h1>
        <p>You can close this window and return to Mac YouTube Uploader.</p>
      </body>
    </html>
    """

    private static func failureHTML(message: String) -> String {
        """
        <!doctype html>
        <html>
          <head><meta charset="utf-8"><title>Connection failed</title></head>
          <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 40px;">
            <h1>Connection failed</h1>
            <p>\(message)</p>
          </body>
        </html>
        """
    }
}
