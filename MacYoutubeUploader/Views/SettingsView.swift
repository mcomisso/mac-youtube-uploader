import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var channels: YouTubeChannelStore
    @State private var presentedLegalDocument: LegalDocumentKind?

    var body: some View {
        TabView {
            apiTab
                .tabItem {
                    Label("YouTube", systemImage: "play.rectangle")
                }

            defaultsTab
                .tabItem {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                }

            uploadsTab
                .tabItem {
                    Label("Uploads", systemImage: "arrow.up.circle")
                }
        }
        .padding(18)
        .background(AppTheme.background)
        .sheet(item: $presentedLegalDocument) { document in
            LegalPolicySheet(document: document)
        }
    }

    private var apiTab: some View {
        SettingsPane {
            SettingsHeader(
                icon: "play.rectangle.fill",
                title: "YouTube API Setup",
                subtitle: "Connect Google with secure OAuth, then choose your upload channel."
            )

            SettingsCard(title: "Privacy & Terms") {
                LegalConsentSettingsView(
                    preferences: preferences,
                    presentedDocument: $presentedLegalDocument
                )
            }

            SettingsCard(title: "Google Sign-In") {
                OAuthClientSettingsView(channels: channels)

                HStack(spacing: 10) {
                    Button {
                        channels.connectGoogleAccount()
                    } label: {
                        Label(
                            channels.isConnecting ? "Connecting..." : "Sign in with Google",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .buttonStyle(PrimaryAppButtonStyle())
                    .disabled(channels.isConnecting)
                    .disabled(!preferences.hasAcceptedRequiredPolicies)
                    .disabled(!channels.oauthConfig.hasClientID)

                    if channels.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()
                }

                if let errorMessage = channels.errorMessage {
                    SettingsInlineMessage(message: errorMessage)
                }
            }

            SettingsCard(title: "Connected Channels") {
                ConnectedChannelsSettingsView(channels: channels)
            }

            SettingsCard(title: "Stored YouTube Data") {
                YouTubeDataControlsView(channels: channels)
            }

            SettingsCard(title: "Upload Playlist") {
                PlaylistSettingsView(channels: channels)
            }
        }
    }

    private var defaultsTab: some View {
        MetadataInspectorView(preferences: preferences)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
    }

    private var uploadsTab: some View {
        SettingsPane {
            SettingsHeader(
                icon: "arrow.up.circle.fill",
                title: "Uploads",
                subtitle: "Keep long transfers visible and resilient while you work."
            )

            SettingsCard(title: "Queue Start") {
                Toggle("Start queue automatically when videos are added", isOn: $preferences.startsUploadsAutomatically)
                    .toggleStyle(.checkbox)

                Text("Leave this off to review each queued item. Turn it on only when you want added videos to upload with the current channel, playlist, privacy, and metadata defaults.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Simultaneous Uploads") {
                Stepper(value: $preferences.maxConcurrentUploads, in: PreferencesStore.concurrentUploadsRange) {
                    Text("Upload up to \(preferences.maxConcurrentUploads) video\(preferences.maxConcurrentUploads == 1 ? "" : "s") at once")
                }

                Text("Lower values give each transfer more bandwidth, so individual videos finish sooner. Queued videos start automatically as uploads complete.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Background Behavior") {
                Toggle("Keep Mac awake while uploads are active", isOn: $preferences.keepMacAwake)
                    .toggleStyle(.checkbox)

                Text("Uploads continue while the app is not frontmost. Keeping the Mac awake helps long transfers finish without sleep interruptions.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard(title: "Menu Bar") {
                Toggle("Show upload status in the menu bar during active uploads", isOn: menuBarIconBinding)
                    .toggleStyle(.checkbox)

                Text("When enabled, the icon appears while uploads are active and hides again when the queue is idle.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding {
            preferences.showsMenuBarIcon
        } set: { isVisible in
            preferences.setShowsMenuBarIcon(isVisible)
        }
    }
}
