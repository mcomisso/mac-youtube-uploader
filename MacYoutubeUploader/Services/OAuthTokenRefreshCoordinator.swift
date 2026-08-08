import Foundation

/// Coalesces refresh-token exchanges per channel so concurrent uploads share
/// one in-flight refresh instead of racing each other and overwriting newer
/// tokens with older ones.
actor OAuthTokenRefreshCoordinator {
    static let shared = OAuthTokenRefreshCoordinator()

    private var inFlightRefreshes: [String: Task<OAuthCredentials, Error>] = [:]

    func refreshIfNeeded(
        _ credentials: OAuthCredentials,
        channelID: String,
        config: OAuthClientConfig,
        oauth: YouTubeOAuthService
    ) async throws -> (credentials: OAuthCredentials, wasRefreshed: Bool) {
        guard credentials.needsRefresh else {
            return (credentials, false)
        }

        if let inFlight = inFlightRefreshes[channelID] {
            return (try await inFlight.value, true)
        }

        let refresh = Task {
            try await oauth.refresh(credentials, config: config)
        }
        inFlightRefreshes[channelID] = refresh
        defer { inFlightRefreshes[channelID] = nil }

        return (try await refresh.value, true)
    }
}
