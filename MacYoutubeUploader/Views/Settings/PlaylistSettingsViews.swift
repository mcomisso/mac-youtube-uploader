import SwiftUI

struct PlaylistSettingsView: View {
    @ObservedObject var channels: YouTubeChannelStore

    var body: some View {
        if channels.selectedChannel == nil {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.field, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("No channel selected.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    Text("Connect a YouTube channel before choosing a playlist.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channels.selectedPlaylist?.title ?? "No playlist selected")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)

                        Text(channels.selectedChannel?.displayName ?? "Selected channel")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        channels.refreshPlaylistsForSelectedChannel()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryAppButtonStyle())
                    .disabled(channels.isRefreshingPlaylists)

                    if channels.isRefreshingPlaylists {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(spacing: 8) {
                    Button {
                        channels.selectPlaylist(id: nil)
                    } label: {
                        PlaylistSettingsRow(
                            title: "No playlist",
                            detail: "Upload videos without adding them to a playlist",
                            systemImage: "minus.circle",
                            isSelected: channels.selectedPlaylistID == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(channels.selectedChannelPlaylists) { playlist in
                        Button {
                            channels.selectPlaylist(id: playlist.id)
                        } label: {
                            PlaylistSettingsRow(
                                title: playlist.title,
                                detail: playlist.detail,
                                systemImage: "list.bullet.rectangle",
                                isSelected: channels.selectedPlaylistID == playlist.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if channels.selectedChannelPlaylists.isEmpty {
                    Text("Refresh playlists to download the playlist list for this channel.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct PlaylistSettingsRow: View {
    var title: String
    var detail: String
    var systemImage: String
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.blue : AppTheme.muted)
                .frame(width: 30, height: 30)
                .background(isSelected ? AppTheme.blueSoft : AppTheme.field, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.blue)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 48)
        .background(isSelected ? AppTheme.blueSoft : AppTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? AppTheme.blue.opacity(0.35) : AppTheme.line, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
