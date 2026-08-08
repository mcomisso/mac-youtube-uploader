import Foundation

struct OAuthClientConfig: Equatable {
    var clientID: String
    var clientSecret: String

    var hasClientID: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var normalizedSecret: String? {
        let trimmed = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct OAuthCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var expiresAt: Date
    var scope: String?

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 90
    }
}

struct AuthorizedChannel: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var title: String
    var handle: String?
    var thumbnailURL: URL?
    var credentials: OAuthCredentials
    var lastSyncedAt: Date? = nil

    var displayName: String {
        if let handle, !handle.isEmpty {
            return "\(title) (\(handle))"
        }
        return title
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AuthorizedChannel, rhs: AuthorizedChannel) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.handle == rhs.handle &&
        lhs.thumbnailURL == rhs.thumbnailURL &&
        lhs.credentials == rhs.credentials &&
        lhs.lastSyncedAt == rhs.lastSyncedAt
    }
}

struct YouTubePlaylist: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var channelID: String
    var title: String
    var itemCount: Int?
    var privacyStatus: String?
    var lastSyncedAt: Date? = nil

    var detail: String {
        var parts: [String] = []

        if let itemCount {
            parts.append("\(itemCount) video\(itemCount == 1 ? "" : "s")")
        }

        if let privacyStatus, !privacyStatus.isEmpty {
            parts.append(privacyStatus.capitalized)
        }

        return parts.isEmpty ? "Playlist" : parts.joined(separator: " - ")
    }
}
