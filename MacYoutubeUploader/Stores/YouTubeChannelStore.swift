import Foundation
import SwiftUI
import Combine

@MainActor
final class YouTubeChannelStore: ObservableObject {
    @Published var oauthClientID: String {
        didSet { UserDefaults.standard.set(oauthClientID, forKey: Keys.oauthClientID) }
    }

    @Published var oauthClientSecret: String {
        didSet { persistOAuthClientSecret() }
    }

    @Published var usesCustomOAuthClient: Bool {
        didSet { UserDefaults.standard.set(usesCustomOAuthClient, forKey: Keys.usesCustomOAuthClient) }
    }

    @Published private(set) var authorizedChannels: [AuthorizedChannel] {
        didSet { persistChannels() }
    }

    @Published private(set) var selectedChannelID: String?

    @Published private(set) var playlistsByChannelID: [String: [YouTubePlaylist]] {
        didSet { persistPlaylists() }
    }

    @Published private(set) var selectedPlaylistIDsByChannelID: [String: String] {
        didSet { persistSelectedPlaylistIDs() }
    }

    @Published var isConnecting = false
    @Published var isRefreshingPlaylists = false
    @Published var isRefreshingStoredYouTubeData = false
    @Published var isRevokingGoogleAccess = false
    @Published var errorMessage: String?

    private let oauth = YouTubeOAuthService()
    private let bundledOAuthConfig: OAuthClientConfig?
    private let hasLegalConsent: @MainActor () -> Bool
    private static let storedAPIDataRefreshInterval: TimeInterval = 30 * 24 * 60 * 60

    init(hasLegalConsent: @escaping @MainActor () -> Bool) {
        self.hasLegalConsent = hasLegalConsent
        self.bundledOAuthConfig = OAuthClientConfigLoader.loadBundledConfig()

        let defaults = UserDefaults.standard
        self.oauthClientID = defaults.string(forKey: Keys.oauthClientID) ?? ""
        let legacyOAuthClientSecret = defaults.string(forKey: Keys.oauthClientSecretLegacy)
        self.oauthClientSecret = (try? KeychainStore.loadString(
            service: Keys.keychainService,
            account: Keys.oauthClientSecretAccount
        )) ?? legacyOAuthClientSecret ?? ""
        self.usesCustomOAuthClient = defaults.object(forKey: Keys.usesCustomOAuthClient) as? Bool ?? false
        self.selectedChannelID = defaults.string(forKey: Keys.selectedChannelID)

        if let data = try? KeychainStore.load(service: Keys.keychainService, account: Keys.channelsAccount),
           let channels = try? JSONDecoder().decode([AuthorizedChannel].self, from: data) {
            self.authorizedChannels = channels
        } else {
            self.authorizedChannels = []
        }

        if let data = try? KeychainStore.load(service: Keys.keychainService, account: Keys.playlistsAccount),
           let playlistsByChannelID = try? JSONDecoder().decode([String: [YouTubePlaylist]].self, from: data) {
            self.playlistsByChannelID = playlistsByChannelID
        } else {
            self.playlistsByChannelID = [:]
        }

        if let data = defaults.data(forKey: Keys.selectedPlaylistIDsByChannelID),
           let selectedPlaylistIDsByChannelID = try? JSONDecoder().decode([String: String].self, from: data) {
            self.selectedPlaylistIDsByChannelID = selectedPlaylistIDsByChannelID
        } else {
            self.selectedPlaylistIDsByChannelID = [:]
        }

        let normalizedSelectedChannelID = normalizedChannelID(selectedChannelID)
        if selectedChannelID != normalizedSelectedChannelID {
            selectedChannelID = normalizedSelectedChannelID
            persistSelectedChannelID()
        }
        normalizeSelectedPlaylistID(for: selectedChannelID)

        // Previous versions stored the tokens without their issuing client.
        // Bind them to the selected client before a later settings change can
        // make refresh requests use a different Google Cloud project.
        let legacyClientConfig = oauthConfig
        if legacyClientConfig.hasClientID {
            var migratedChannels = authorizedChannels
            for index in migratedChannels.indices where migratedChannels[index].credentials.clientConfig == nil {
                migratedChannels[index].credentials.clientConfig = legacyClientConfig
            }
            if migratedChannels != authorizedChannels {
                authorizedChannels = migratedChannels
                persistChannels()
            }
        }

        if legacyOAuthClientSecret != nil {
            persistOAuthClientSecret()
            defaults.removeObject(forKey: Keys.oauthClientSecretLegacy)
        }

        Task {
            await refreshStoredYouTubeDataIfNeeded()
        }
    }

    var selectedChannel: AuthorizedChannel? {
        guard let selectedChannelID else { return nil }
        return authorizedChannels.first(where: { $0.id == selectedChannelID })
    }

    var selectedChannelPlaylists: [YouTubePlaylist] {
        guard let selectedChannelID else { return [] }
        return playlistsByChannelID[selectedChannelID] ?? []
    }

    var selectedPlaylistID: String? {
        guard let selectedChannelID else { return nil }
        return selectedPlaylistID(for: selectedChannelID)
    }

    var selectedPlaylist: YouTubePlaylist? {
        guard let selectedChannelID, let selectedPlaylistID else { return nil }
        return playlist(id: selectedPlaylistID, channelID: selectedChannelID)
    }

    var oauthConfig: OAuthClientConfig {
        let manualConfig = OAuthClientConfig(clientID: oauthClientID, clientSecret: oauthClientSecret)
        if usesCustomOAuthClient {
            return manualConfig
        }
        return bundledOAuthConfig ?? manualConfig
    }

    func oauthConfig(for channel: AuthorizedChannel) -> OAuthClientConfig {
        channel.credentials.oauthConfig(fallback: oauthConfig)
    }

    var hasBundledOAuthConfig: Bool {
        bundledOAuthConfig?.hasClientID == true
    }

    var isUsingBundledOAuthConfig: Bool {
        !usesCustomOAuthClient && hasBundledOAuthConfig
    }

    var hasCustomOAuthConfig: Bool {
        OAuthClientConfig(clientID: oauthClientID, clientSecret: oauthClientSecret).hasClientID
    }

    func connectGoogleAccount() {
        guard !isConnecting else { return }
        guard hasLegalConsent() else {
            errorMessage = AppError.legalAgreementRequired.localizedDescription
            return
        }
        guard oauthConfig.hasClientID else {
            errorMessage = AppError.missingOAuthClientID.localizedDescription
            return
        }

        let config = oauthConfig
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                let credentials = try await oauth.signIn(config: config)
                let channels = try await oauth.fetchChannels(
                    accessToken: credentials.accessToken,
                    credentials: credentials
                )

                merge(channels)
                normalizeSelectedChannelID()
                if let selectedChannel {
                    try await refreshPlaylists(for: selectedChannel)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    func importOAuthClientConfig(from url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let config = try OAuthClientConfigLoader.importConfig(from: url)
            oauthClientID = config.clientID
            oauthClientSecret = config.clientSecret
            usesCustomOAuthClient = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectChannel(id: String?) {
        let normalizedID = normalizedChannelID(id)
        guard selectedChannelID != normalizedID else { return }
        selectedChannelID = normalizedID
        persistSelectedChannelID()
        normalizeSelectedPlaylistID(for: normalizedID)
    }

    func selectedPlaylistID(for channelID: String) -> String? {
        normalizedPlaylistID(selectedPlaylistIDsByChannelID[channelID], channelID: channelID)
    }

    func playlist(id: String, channelID: String) -> YouTubePlaylist? {
        playlistsByChannelID[channelID]?.first { $0.id == id }
    }

    func selectPlaylist(id: String?) {
        guard let selectedChannelID else { return }
        selectPlaylist(id: id, for: selectedChannelID)
    }

    func refreshPlaylistsForSelectedChannel() {
        guard !isRefreshingPlaylists else { return }
        guard hasLegalConsent() else {
            errorMessage = AppError.legalAgreementRequired.localizedDescription
            return
        }
        guard let selectedChannel else {
            errorMessage = AppError.noSelectedChannel.localizedDescription
            return
        }

        isRefreshingPlaylists = true
        errorMessage = nil

        Task {
            do {
                try await refreshPlaylists(for: selectedChannel)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefreshingPlaylists = false
        }
    }

    func updateCredentials(_ credentials: OAuthCredentials, for channelID: String) {
        guard let index = authorizedChannels.firstIndex(where: { $0.id == channelID }) else {
            return
        }
        var updatedChannels = authorizedChannels
        var updatedCredentials = credentials
        if updatedCredentials.clientConfig == nil {
            updatedCredentials.clientConfig = updatedChannels[index].credentials.clientConfig
        }
        updatedChannels[index].credentials = updatedCredentials
        authorizedChannels = updatedChannels
    }

    func disconnectSelectedChannel() {
        guard let selectedChannelID else { return }
        authorizedChannels.removeAll { $0.id == selectedChannelID }
        removePlaylists(for: selectedChannelID)
        normalizeSelectedChannelID()
    }

    func deleteStoredYouTubeData() {
        deleteStoredYouTubeDataLocally()
    }

    func revokeGoogleAccessAndDeleteStoredYouTubeData() {
        guard !isRevokingGoogleAccess else { return }
        let credentials = uniqueCredentialSnapshots()
        guard !credentials.isEmpty else {
            deleteStoredYouTubeDataLocally()
            return
        }

        isRevokingGoogleAccess = true
        errorMessage = nil

        Task {
            var revocationFailures: [String] = []
            for credential in credentials {
                do {
                    try await oauth.revoke(credential)
                } catch {
                    revocationFailures.append(error.localizedDescription)
                }
            }

            deleteStoredYouTubeDataLocally()
            if !revocationFailures.isEmpty {
                errorMessage = "Local YouTube data was deleted, but Google access revocation did not complete. Remove access from your Google account permissions page."
            }
            isRevokingGoogleAccess = false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshStoredYouTubeDataIfNeeded() async {
        guard storedYouTubeDataNeedsRefresh else { return }

        guard hasLegalConsent() else {
            deleteStoredYouTubeDataLocally()
            errorMessage = "Stored YouTube data was older than 30 days and was deleted because the current privacy policy and terms have not been accepted."
            return
        }

        guard authorizedChannels.allSatisfy({ oauthConfig(for: $0).hasClientID }) else {
            deleteStoredYouTubeDataLocally()
            errorMessage = "Stored YouTube data was older than 30 days and could not be refreshed because no OAuth client is configured. Connect YouTube again to continue."
            return
        }

        isRefreshingStoredYouTubeData = true
        defer { isRefreshingStoredYouTubeData = false }

        do {
            try await refreshAllStoredYouTubeData()
        } catch {
            deleteStoredYouTubeDataLocally()
            errorMessage = "Stored YouTube data was older than 30 days and could not be refreshed. Connect YouTube again to continue."
        }
    }

    private func merge(_ channels: [AuthorizedChannel]) {
        var mergedChannels = authorizedChannels

        for channel in channels {
            if let index = mergedChannels.firstIndex(where: { $0.id == channel.id }) {
                mergedChannels[index] = channel
            } else {
                mergedChannels.append(channel)
            }
        }

        guard authorizedChannels != mergedChannels else { return }
        authorizedChannels = mergedChannels
    }

    private func normalizeSelectedChannelID() {
        selectChannel(id: selectedChannelID)
    }

    private func normalizedChannelID(_ channelID: String?) -> String? {
        if let channelID, authorizedChannels.contains(where: { $0.id == channelID }) {
            return channelID
        }

        return authorizedChannels.first?.id
    }

    private func refreshPlaylists(for channel: AuthorizedChannel) async throws {
        var credentials = channel.credentials
        if credentials.needsRefresh {
            credentials = try await oauth.refresh(credentials, config: oauthConfig(for: channel))
            updateCredentials(credentials, for: channel.id)
        }

        let playlists = try await oauth.fetchPlaylists(
            accessToken: credentials.accessToken,
            channelID: channel.id
        )

        var updatedPlaylists = playlistsByChannelID
        updatedPlaylists[channel.id] = playlists
        playlistsByChannelID = updatedPlaylists
        normalizeSelectedPlaylistID(for: channel.id)
    }

    private var storedYouTubeDataNeedsRefresh: Bool {
        authorizedChannels.contains { isExpiredAPIData(timestamp: $0.lastSyncedAt) } ||
            playlistsByChannelID.values.flatMap { $0 }.contains { isExpiredAPIData(timestamp: $0.lastSyncedAt) }
    }

    private func isExpiredAPIData(timestamp: Date?) -> Bool {
        guard let timestamp else { return true }
        return Date().timeIntervalSince(timestamp) >= Self.storedAPIDataRefreshInterval
    }

    private func refreshAllStoredYouTubeData() async throws {
        var refreshedChannels: [AuthorizedChannel] = []

        for credential in uniqueCredentialSnapshots() {
            var credentials = credential
            if credentials.needsRefresh {
                credentials = try await oauth.refresh(
                    credentials,
                    config: credentials.oauthConfig(fallback: oauthConfig)
                )
            }

            let channels = try await oauth.fetchChannels(
                accessToken: credentials.accessToken,
                credentials: credentials
            )
            refreshedChannels.append(contentsOf: channels)
        }

        let deduplicatedChannels = deduplicated(refreshedChannels)
        guard !deduplicatedChannels.isEmpty else {
            deleteStoredYouTubeDataLocally()
            return
        }

        authorizedChannels = deduplicatedChannels
        normalizeSelectedChannelID()

        var refreshedPlaylists: [String: [YouTubePlaylist]] = [:]
        for channel in deduplicatedChannels {
            let playlists = try await oauth.fetchPlaylists(
                accessToken: channel.credentials.accessToken,
                channelID: channel.id
            )
            refreshedPlaylists[channel.id] = playlists
        }

        playlistsByChannelID = refreshedPlaylists
        selectedPlaylistIDsByChannelID = selectedPlaylistIDsByChannelID.filter { channelID, playlistID in
            refreshedPlaylists[channelID]?.contains(where: { $0.id == playlistID }) == true
        }
        for channelID in refreshedPlaylists.keys {
            normalizeSelectedPlaylistID(for: channelID)
        }
    }

    private func deduplicated(_ channels: [AuthorizedChannel]) -> [AuthorizedChannel] {
        var seenIDs = Set<String>()
        var result: [AuthorizedChannel] = []

        for channel in channels {
            guard seenIDs.insert(channel.id).inserted else { continue }
            result.append(channel)
        }

        return result.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func uniqueCredentialSnapshots() -> [OAuthCredentials] {
        var seenTokens = Set<String>()
        var credentials: [OAuthCredentials] = []

        for channel in authorizedChannels {
            let tokenKey = channel.credentials.refreshToken.isEmpty
                ? channel.credentials.accessToken
                : channel.credentials.refreshToken
            guard !tokenKey.isEmpty, seenTokens.insert(tokenKey).inserted else { continue }
            credentials.append(channel.credentials)
        }

        return credentials
    }

    private func selectPlaylist(id: String?, for channelID: String) {
        let normalizedID = normalizedPlaylistID(id, channelID: channelID)
        var updatedSelections = selectedPlaylistIDsByChannelID
        if let normalizedID {
            updatedSelections[channelID] = normalizedID
        } else {
            updatedSelections.removeValue(forKey: channelID)
        }

        guard selectedPlaylistIDsByChannelID != updatedSelections else { return }
        selectedPlaylistIDsByChannelID = updatedSelections
    }

    private func normalizeSelectedPlaylistID(for channelID: String?) {
        guard let channelID else { return }
        selectPlaylist(id: selectedPlaylistIDsByChannelID[channelID], for: channelID)
    }

    private func normalizedPlaylistID(_ playlistID: String?, channelID: String) -> String? {
        guard let playlistID,
              playlistsByChannelID[channelID]?.contains(where: { $0.id == playlistID }) == true else {
            return nil
        }
        return playlistID
    }

    private func removePlaylists(for channelID: String) {
        var updatedPlaylists = playlistsByChannelID
        updatedPlaylists.removeValue(forKey: channelID)
        playlistsByChannelID = updatedPlaylists

        var updatedSelections = selectedPlaylistIDsByChannelID
        updatedSelections.removeValue(forKey: channelID)
        selectedPlaylistIDsByChannelID = updatedSelections
    }

    private func deleteStoredYouTubeDataLocally() {
        authorizedChannels = []
        playlistsByChannelID = [:]
        selectedPlaylistIDsByChannelID = [:]
        selectedChannelID = nil
        persistSelectedChannelID()

        try? KeychainStore.delete(service: Keys.keychainService, account: Keys.channelsAccount)
        try? KeychainStore.delete(service: Keys.keychainService, account: Keys.playlistsAccount)
        UserDefaults.standard.removeObject(forKey: Keys.selectedPlaylistIDsByChannelID)
    }

    private func persistChannels() {
        guard !authorizedChannels.isEmpty else {
            try? KeychainStore.delete(service: Keys.keychainService, account: Keys.channelsAccount)
            return
        }
        guard let data = try? JSONEncoder().encode(authorizedChannels) else { return }
        try? KeychainStore.save(data, service: Keys.keychainService, account: Keys.channelsAccount)
    }

    private func persistOAuthClientSecret() {
        try? KeychainStore.saveString(
            oauthClientSecret,
            service: Keys.keychainService,
            account: Keys.oauthClientSecretAccount
        )
    }

    private func persistPlaylists() {
        guard !playlistsByChannelID.isEmpty else {
            try? KeychainStore.delete(service: Keys.keychainService, account: Keys.playlistsAccount)
            return
        }
        guard let data = try? JSONEncoder().encode(playlistsByChannelID) else { return }
        try? KeychainStore.save(data, service: Keys.keychainService, account: Keys.playlistsAccount)
    }

    private func persistSelectedPlaylistIDs() {
        guard !selectedPlaylistIDsByChannelID.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedPlaylistIDsByChannelID)
            return
        }
        guard let data = try? JSONEncoder().encode(selectedPlaylistIDsByChannelID) else { return }
        UserDefaults.standard.set(data, forKey: Keys.selectedPlaylistIDsByChannelID)
    }

    private func persistSelectedChannelID() {
        if let selectedChannelID {
            UserDefaults.standard.set(selectedChannelID, forKey: Keys.selectedChannelID)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedChannelID)
        }
    }
}

private enum Keys {
    static let oauthClientID = "oauth.clientID"
    static let oauthClientSecretLegacy = "oauth.clientSecret"
    static let usesCustomOAuthClient = "oauth.usesCustomClient"
    static let selectedChannelID = "youtube.selectedChannelID"
    static let selectedPlaylistIDsByChannelID = "youtube.selectedPlaylistIDsByChannelID"
    static let keychainService = "com.matcom.MacYouTubeUploader"
    static let oauthClientSecretAccount = "oauth-client-secret"
    static let channelsAccount = "authorized-channels"
    static let playlistsAccount = "authorized-playlists"
}
