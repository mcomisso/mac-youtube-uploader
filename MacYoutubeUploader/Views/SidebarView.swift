import SwiftUI

struct SidebarView: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var channels: YouTubeChannelStore
    @Binding var selection: QueueFilter?

    var body: some View {
        List(selection: $selection) {
            Section {
                BrandSidebarRow()
                    .padding(.vertical, 6)
            }

            Section("Uploads") {
                ForEach(QueueFilter.allCases) { filter in
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.systemImage)
                    }
                    .badge(filter.count(in: uploads.jobs))
                    .tag(filter)
                }
            }

            Section("Channels") {
                if channels.authorizedChannels.isEmpty {
                    Button {
                        channels.connectGoogleAccount()
                    } label: {
                        Label(
                            channels.isConnecting ? "Connecting..." : "Connect Google",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(channels.isConnecting)
                } else {
                    ForEach(channels.authorizedChannels) { channel in
                        Button {
                            channels.selectChannel(id: channel.id)
                        } label: {
                            ChannelSidebarRow(
                                channel: channel,
                                isSelected: channels.selectedChannelID == channel.id
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        channels.connectGoogleAccount()
                    } label: {
                        Label("Add Channel", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .disabled(channels.isConnecting)
                }
            }

            Section {
                SettingsLink {
                    Label("Upload Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            SidebarFooterView(keepMacAwake: preferences.keepMacAwake)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}

private struct BrandSidebarRow: View {
    var body: some View {
        HStack(spacing: 10) {
            BrandMarkView(size: 28)

            Text("Mac YouTube Uploader")
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChannelSidebarRow: View {
    var channel: AuthorizedChannel
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "person.crop.circle")
                .foregroundStyle(isSelected ? AppTheme.blue : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title)
                    .lineLimit(1)

                if let handle = channel.handle, !handle.isEmpty {
                    Text(handle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct SidebarFooterView: View {
    var keepMacAwake: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Circle()
                    .fill(AppTheme.green)
                    .frame(width: 8, height: 8)

                Text("Background uploads enabled")
                    .font(.caption.weight(.medium))
            }

            Text(keepMacAwake ? "The Mac stays awake while uploads are active." : "Uploads continue while the Mac is awake.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
