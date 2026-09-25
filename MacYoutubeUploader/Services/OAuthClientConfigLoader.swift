import Foundation

enum OAuthClientConfigImportError: LocalizedError {
    case unreadable
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "The selected file could not be read."
        case .invalidFormat:
            "The selected file is not a Google OAuth desktop client JSON file. Download a Desktop app client JSON from Google Cloud Console and try again."
        }
    }
}

enum OAuthClientConfigLoader {
    static func loadBundledConfig() -> OAuthClientConfig? {
        [
            loadEnvironmentConfig(),
            loadInfoDictionaryConfig(),
            loadFileConfig()
        ]
        .compactMap { $0 }
        .first
    }

    static func importConfig(from url: URL) throws -> OAuthClientConfig {
        guard let data = try? Data(contentsOf: url) else {
            throw OAuthClientConfigImportError.unreadable
        }

        guard let credentials = try? JSONDecoder().decode(GoogleOAuthClientJSON.self, from: data),
              let client = credentials.installed else {
            throw OAuthClientConfigImportError.invalidFormat
        }

        let config = OAuthClientConfig(
            clientID: client.clientID,
            clientSecret: client.clientSecret ?? ""
        )
        guard config.hasClientID else {
            throw OAuthClientConfigImportError.invalidFormat
        }

        return config
    }

    private static func loadEnvironmentConfig() -> OAuthClientConfig? {
        let environment = ProcessInfo.processInfo.environment
        let clientID = normalized(environment["YOUTUBE_OAUTH_CLIENT_ID"])
        guard !clientID.isEmpty else { return nil }

        return OAuthClientConfig(
            clientID: clientID,
            clientSecret: normalized(environment["YOUTUBE_OAUTH_CLIENT_SECRET"])
        )
    }

    private static func loadInfoDictionaryConfig() -> OAuthClientConfig? {
        let clientID = normalized(Bundle.main.object(forInfoDictionaryKey: "YouTubeOAuthClientID") as? String)
        guard !clientID.isEmpty else { return nil }

        return OAuthClientConfig(
            clientID: clientID,
            clientSecret: normalized(Bundle.main.object(forInfoDictionaryKey: "YouTubeOAuthClientSecret") as? String)
        )
    }

    private static func loadFileConfig() -> OAuthClientConfig? {
        for url in candidateURLs() {
            if let config = loadConfig(from: url) {
                return config
            }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []

        if let environmentPath = ProcessInfo.processInfo.environment["YOUTUBE_OAUTH_CLIENT_JSON"],
           !environmentPath.isEmpty {
            urls.append(URL(fileURLWithPath: environmentPath))
        }

        let sourceRelativeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/OAuthClient/client_secret.json")
        urls.append(sourceRelativeURL)

        return urls
    }

    private static func loadConfig(from url: URL) -> OAuthClientConfig? {
        try? importConfig(from: url)
    }

    private static func normalized(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.hasPrefix("$(") else { return "" }
        return trimmed
    }
}

private struct GoogleOAuthClientJSON: Decodable {
    var installed: GoogleOAuthClient?
}

private struct GoogleOAuthClient: Decodable {
    var clientID: String
    var clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}
