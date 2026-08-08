import SwiftUI

struct YouTubeDataControlsView: View {
    @ObservedObject var channels: YouTubeChannelStore
    @State private var pendingAction: StoredYouTubeDataAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if channels.isRefreshingStoredYouTubeData {
                Label("Refreshing stored YouTube data", systemImage: "arrow.clockwise")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
            }

            Text("Delete connected channel credentials, channel details, playlist metadata, and playlist selections stored by this app. This does not delete videos, playlists, or other data stored by YouTube.")
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    pendingAction = .deleteLocal
                } label: {
                    Label("Delete Local Data", systemImage: "trash")
                }
                .buttonStyle(SecondaryAppButtonStyle())
                .disabled(channels.authorizedChannels.isEmpty)

                Button(role: .destructive) {
                    pendingAction = .revokeAndDelete
                } label: {
                    Label(
                        channels.isRevokingGoogleAccess ? "Revoking..." : "Revoke & Delete",
                        systemImage: "xmark.shield"
                    )
                }
                .buttonStyle(SecondaryAppButtonStyle())
                .disabled(channels.authorizedChannels.isEmpty || channels.isRevokingGoogleAccess)

                Link("Google Permissions", destination: AppLegal.googlePermissionsURL)
                    .buttonStyle(SecondaryAppButtonStyle())
            }
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.confirmationButtonTitle, role: .destructive) {
                    perform(pendingAction)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding {
            pendingAction != nil
        } set: { isPresented in
            if !isPresented {
                pendingAction = nil
            }
        }
    }

    private func perform(_ action: StoredYouTubeDataAction) {
        switch action {
        case .deleteLocal:
            channels.deleteStoredYouTubeData()
        case .revokeAndDelete:
            channels.revokeGoogleAccessAndDeleteStoredYouTubeData()
        }
        pendingAction = nil
    }
}

enum StoredYouTubeDataAction: Identifiable {
    case deleteLocal
    case revokeAndDelete

    var id: String {
        switch self {
        case .deleteLocal: "delete-local"
        case .revokeAndDelete: "revoke-and-delete"
        }
    }

    var title: String {
        switch self {
        case .deleteLocal: "Delete local YouTube data?"
        case .revokeAndDelete: "Revoke Google access?"
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .deleteLocal: "Delete Local Data"
        case .revokeAndDelete: "Revoke and Delete"
        }
    }

    var message: String {
        switch self {
        case .deleteLocal:
            "This removes YouTube credentials and cached YouTube API data stored by this app. It does not delete anything on YouTube."
        case .revokeAndDelete:
            "This asks Google to revoke the stored OAuth token, then removes YouTube credentials and cached YouTube API data stored by this app."
        }
    }
}
