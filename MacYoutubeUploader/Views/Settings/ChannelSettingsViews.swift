import SwiftUI

struct ConnectedChannelsSettingsView: View {
    @ObservedObject var channels: YouTubeChannelStore

    var body: some View {
        if channels.authorizedChannels.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.field, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("No channel connected.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    Text("Sign in above to add the YouTube channels available to this Google account.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 8) {
                    ForEach(channels.authorizedChannels) { channel in
                        Button {
                            channels.selectChannel(id: channel.id)
                        } label: {
                            ChannelSettingsRow(
                                channel: channel,
                                isSelected: channels.selectedChannelID == channel.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        channels.connectGoogleAccount()
                    } label: {
                        Label(
                            channels.isConnecting ? "Connecting..." : "Add Channel",
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(SecondaryAppButtonStyle())
                    .disabled(channels.isConnecting)

                    if channels.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        channels.disconnectSelectedChannel()
                    } label: {
                        Label("Disconnect", systemImage: "trash")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppTheme.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(channels.selectedChannelID == nil)
                }
            }
        }
    }
}

struct ChannelSettingsRow: View {
    var channel: AuthorizedChannel
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            ChannelInitialBadge(title: channel.title, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                Text(channelSubtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if isSelected {
                Label("Default", systemImage: "checkmark.circle.fill")
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

    private var channelSubtitle: String {
        if let handle = channel.handle, !handle.isEmpty {
            return handle
        }

        return "YouTube channel"
    }
}

struct ChannelInitialBadge: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isSelected
                    ? [AppTheme.blue, AppTheme.blueHighlight]
                    : [AppTheme.red, Color(hex: 0xFFB347)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initial)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }

    private var initial: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "Y"
    }
}
