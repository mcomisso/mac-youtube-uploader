import Foundation
import SwiftUI
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var metadata: MetadataDefaults {
        didSet { persistMetadata() }
    }

    @Published var keepMacAwake: Bool {
        didSet { UserDefaults.standard.set(keepMacAwake, forKey: Keys.keepMacAwake) }
    }

    @Published var startsUploadsAutomatically: Bool {
        didSet { UserDefaults.standard.set(startsUploadsAutomatically, forKey: Keys.startsUploadsAutomatically) }
    }

    @Published var maxConcurrentUploads: Int {
        didSet {
            let clamped = Self.clampedConcurrentUploads(maxConcurrentUploads)
            if maxConcurrentUploads != clamped {
                maxConcurrentUploads = clamped
                return
            }
            UserDefaults.standard.set(maxConcurrentUploads, forKey: Keys.maxConcurrentUploads)
        }
    }

    @Published private(set) var showsMenuBarIcon: Bool
    @Published private(set) var acceptedLegalAgreementVersion: String?

    private(set) lazy var channels = YouTubeChannelStore(
        hasLegalConsent: { [weak self] in self?.hasAcceptedRequiredPolicies ?? false }
    )

    private var channelsObservation: AnyCancellable?

    static let defaultMaxConcurrentUploads = 3
    static let concurrentUploadsRange = 1...6

    private static func clampedConcurrentUploads(_ value: Int) -> Int {
        min(max(value, concurrentUploadsRange.lowerBound), concurrentUploadsRange.upperBound)
    }

    init() {
        let defaults = UserDefaults.standard
        if let metadataData = defaults.data(forKey: Keys.metadata),
           let metadata = try? JSONDecoder().decode(MetadataDefaults.self, from: metadataData) {
            self.metadata = metadata
        } else {
            self.metadata = MetadataDefaults()
        }

        self.keepMacAwake = defaults.object(forKey: Keys.keepMacAwake) as? Bool ?? true
        self.startsUploadsAutomatically = defaults.object(forKey: Keys.startsUploadsAutomatically) as? Bool ?? false
        self.maxConcurrentUploads = Self.clampedConcurrentUploads(
            defaults.object(forKey: Keys.maxConcurrentUploads) as? Int ?? Self.defaultMaxConcurrentUploads
        )
        self.showsMenuBarIcon = defaults.object(forKey: Keys.showsMenuBarIcon) as? Bool ?? false
        self.acceptedLegalAgreementVersion = defaults.string(forKey: Keys.acceptedLegalAgreementVersion)

        // Forward channel-store changes so observers of the facade members
        // below keep re-rendering as they did before the split.
        channelsObservation = channels.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var hasAcceptedRequiredPolicies: Bool {
        acceptedLegalAgreementVersion == AppLegal.currentAgreementVersion
    }

    func acceptRequiredPolicies() {
        acceptedLegalAgreementVersion = AppLegal.currentAgreementVersion
        UserDefaults.standard.set(AppLegal.currentAgreementVersion, forKey: Keys.acceptedLegalAgreementVersion)
        Task {
            await channels.refreshStoredYouTubeDataIfNeeded()
        }
    }

    func setShowsMenuBarIcon(_ isVisible: Bool) {
        guard showsMenuBarIcon != isVisible else { return }
        showsMenuBarIcon = isVisible
        UserDefaults.standard.set(isVisible, forKey: Keys.showsMenuBarIcon)
    }

    private func persistMetadata() {
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        UserDefaults.standard.set(data, forKey: Keys.metadata)
    }
}

// MARK: - Channel state facade
// Keeps PreferencesStore satisfying UploadPreferencesProviding (declared in
// UploadStore.swift) after the channel concerns moved to YouTubeChannelStore.
extension PreferencesStore {
    var selectedChannelID: String? {
        channels.selectedChannelID
    }

    var selectedChannel: AuthorizedChannel? {
        channels.selectedChannel
    }

    var authorizedChannels: [AuthorizedChannel] {
        channels.authorizedChannels
    }

    var selectedPlaylistID: String? {
        channels.selectedPlaylistID
    }

    var oauthConfig: OAuthClientConfig {
        channels.oauthConfig
    }

    func oauthConfig(for channel: AuthorizedChannel) -> OAuthClientConfig {
        channels.oauthConfig(for: channel)
    }

    func selectedPlaylistID(for channelID: String) -> String? {
        channels.selectedPlaylistID(for: channelID)
    }

    func playlist(id: String, channelID: String) -> YouTubePlaylist? {
        channels.playlist(id: id, channelID: channelID)
    }

    func updateCredentials(_ credentials: OAuthCredentials, for channelID: String) {
        channels.updateCredentials(credentials, for: channelID)
    }
}

private enum Keys {
    static let metadata = "metadata.defaults"
    static let keepMacAwake = "uploads.keepMacAwake"
    static let startsUploadsAutomatically = "uploads.startsUploadsAutomatically"
    static let maxConcurrentUploads = "uploads.maxConcurrentUploads"
    static let showsMenuBarIcon = "uploads.showsMenuBarIcon"
    static let acceptedLegalAgreementVersion = "legal.acceptedAgreementVersion"
}
