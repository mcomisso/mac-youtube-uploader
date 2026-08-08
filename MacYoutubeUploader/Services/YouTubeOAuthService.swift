import AppKit
import Foundation

struct YouTubeOAuthService {
    private let scopes = [
        "https://www.googleapis.com/auth/youtube.force-ssl"
    ]

    func signIn(config: OAuthClientConfig) async throws -> OAuthCredentials {
        guard config.hasClientID else {
            throw AppError.missingOAuthClientID
        }

        let verifier = PKCE.verifier()
        let state = PKCE.state()
        let server = try OAuthLoopbackServer(expectedState: state)
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)\(OAuthLoopbackServer.callbackPath)"
        let authURL = try authorizationURL(
            config: config,
            redirectURI: redirectURI,
            verifier: verifier,
            state: state
        )

        await MainActor.run {
            _ = NSWorkspace.shared.open(authURL)
        }

        let callback = try await server.waitForCallback()
        guard callback.state == state else {
            throw AppError.oauthStateMismatch
        }

        return try await exchangeCode(
            callback.code,
            redirectURI: redirectURI,
            verifier: verifier,
            config: config
        )
    }

    func refresh(_ credentials: OAuthCredentials, config: OAuthClientConfig) async throws -> OAuthCredentials {
        guard !credentials.refreshToken.isEmpty else {
            throw AppError.missingRefreshToken
        }

        var fields: [String: String] = [
            "client_id": config.clientID,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token"
        ]
        if let secret = config.normalizedSecret {
            fields["client_secret"] = secret
        }

        let response: TokenResponse = try await postToken(fields: fields)
        return OAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: credentials.refreshToken,
            tokenType: response.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(response.expiresIn - 60, 60))),
            scope: response.scope ?? credentials.scope
        )
    }

    func revoke(_ credentials: OAuthCredentials) async throws {
        let token = credentials.refreshToken.isEmpty ? credentials.accessToken : credentials.refreshToken
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ["token": token].formURLEncoded().data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
    }

    func fetchChannels(accessToken: String, credentials: OAuthCredentials) async throws -> [AuthorizedChannel] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "mine", value: "true")
        ]

        let request = Self.authorizedRequest(url: components.url!, accessToken: accessToken)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        let list = try JSONDecoder().decode(ChannelListResponse.self, from: data)
        let syncedAt = Date()
        let channels = list.items.map { item in
            AuthorizedChannel(
                id: item.id,
                title: item.snippet.title,
                handle: item.snippet.customUrl,
                thumbnailURL: item.snippet.thumbnails.defaultImage?.url,
                credentials: credentials,
                lastSyncedAt: syncedAt
            )
        }

        guard !channels.isEmpty else {
            throw AppError.noYouTubeChannel
        }

        return channels
    }

    func fetchPlaylists(accessToken: String, channelID: String) async throws -> [YouTubePlaylist] {
        var playlists: [YouTubePlaylist] = []
        var nextPageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlists")!
            var queryItems = [
                URLQueryItem(name: "part", value: "snippet,contentDetails,status"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            if let nextPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }
            components.queryItems = queryItems

            let request = Self.authorizedRequest(url: components.url!, accessToken: accessToken)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.validate(response: response, data: data)

            let list = try JSONDecoder().decode(PlaylistListResponse.self, from: data)
            let syncedAt = Date()
            playlists.append(contentsOf: list.items.map { item in
                YouTubePlaylist(
                    id: item.id,
                    channelID: channelID,
                    title: item.snippet.title,
                    itemCount: item.contentDetails?.itemCount,
                    privacyStatus: item.status?.privacyStatus,
                    lastSyncedAt: syncedAt
                )
            })
            nextPageToken = list.nextPageToken
        } while nextPageToken != nil

        return playlists.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func authorizationURL(
        config: OAuthClientConfig,
        redirectURI: String,
        verifier: String,
        state: String
    ) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    private func exchangeCode(
        _ code: String,
        redirectURI: String,
        verifier: String,
        config: OAuthClientConfig
    ) async throws -> OAuthCredentials {
        var fields: [String: String] = [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        if let secret = config.normalizedSecret {
            fields["client_secret"] = secret
        }

        let response: TokenResponse = try await postToken(fields: fields)
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw AppError.missingRefreshToken
        }

        return OAuthCredentials(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            tokenType: response.tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(response.expiresIn - 60, 60))),
            scope: response.scope
        )
    }

    private func postToken<T: Decodable>(fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields.formURLEncoded().data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AppError.invalidHTTPStatus(http.statusCode, body)
        }
    }

    private static func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String?
    var tokenType: String
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }
}

private struct ChannelListResponse: Decodable {
    var items: [ChannelItem]
}

private struct ChannelItem: Decodable {
    var id: String
    var snippet: ChannelSnippet
}

private struct ChannelSnippet: Decodable {
    var title: String
    var customUrl: String?
    var thumbnails: ChannelThumbnails
}

private struct ChannelThumbnails: Decodable {
    var defaultImage: ChannelThumbnail?

    enum CodingKeys: String, CodingKey {
        case defaultImage = "default"
    }
}

private struct ChannelThumbnail: Decodable {
    var url: URL
}

private struct PlaylistListResponse: Decodable {
    var nextPageToken: String?
    var items: [PlaylistListItem]
}

private struct PlaylistListItem: Decodable {
    var id: String
    var snippet: PlaylistSnippet
    var contentDetails: PlaylistContentDetails?
    var status: PlaylistStatus?
}

private struct PlaylistSnippet: Decodable {
    var title: String
}

private struct PlaylistContentDetails: Decodable {
    var itemCount: Int?
}

private struct PlaylistStatus: Decodable {
    var privacyStatus: String?
}

private extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> String {
        map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .sorted()
        .joined(separator: "&")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}
