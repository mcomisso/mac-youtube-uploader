import SwiftUI
import UniformTypeIdentifiers

struct OAuthClientSettingsView: View {
    @ObservedObject var channels: YouTubeChannelStore
    @State private var isImportingClientJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(statusTitle, systemImage: statusIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(statusColor)

            Text(statusDetail)
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .background(AppTheme.line)

            Toggle("Expert: use my own Google Cloud OAuth client", isOn: $channels.usesCustomOAuthClient)
                .toggleStyle(.checkbox)

            if channels.usesCustomOAuthClient || !channels.hasBundledOAuthConfig {
                Button {
                    isImportingClientJSON = true
                } label: {
                    Label("Import Client JSON...", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SecondaryAppButtonStyle())
                .fileImporter(
                    isPresented: $isImportingClientJSON,
                    allowedContentTypes: [.json]
                ) { result in
                    if case .success(let url) = result {
                        channels.importOAuthClientConfig(from: url)
                    }
                }

                Text("Load the client ID and secret from a client_secret.json file downloaded from Google Cloud Console. The values are stored, so this is only needed once.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if channels.usesCustomOAuthClient {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use this only when you want uploads to run through your own Google Cloud project and YouTube API quota.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    LabeledSettingField(title: "Client ID") {
                        TextField("Client ID", text: $channels.oauthClientID)
                            .textFieldStyle(.plain)
                            .appInput()
                    }

                    LabeledSettingField(title: "Client secret") {
                        SecureField("Client secret, if your OAuth client has one", text: $channels.oauthClientSecret)
                            .textFieldStyle(.plain)
                            .appInput()
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        if channels.usesCustomOAuthClient {
            return channels.hasCustomOAuthConfig
                ? "Using custom Google Cloud OAuth client"
                : "Custom OAuth client required"
        }

        return channels.hasBundledOAuthConfig
            ? "Using app Google OAuth client"
            : "App OAuth client not configured"
    }

    private var statusDetail: String {
        if channels.usesCustomOAuthClient {
            return "Expert mode replaces the app client with your own Google Cloud OAuth client."
        }

        return channels.hasBundledOAuthConfig
            ? "Most users can sign in with Google without creating API credentials."
            : "Set the production OAuth client ID in the app build settings before distribution."
    }

    private var statusIcon: String {
        switch (channels.usesCustomOAuthClient, channels.hasBundledOAuthConfig, channels.hasCustomOAuthConfig) {
        case (true, _, true), (false, true, _):
            "checkmark.seal.fill"
        default:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch (channels.usesCustomOAuthClient, channels.hasBundledOAuthConfig, channels.hasCustomOAuthConfig) {
        case (true, _, true), (false, true, _):
            AppTheme.green
        default:
            AppTheme.orange
        }
    }
}
