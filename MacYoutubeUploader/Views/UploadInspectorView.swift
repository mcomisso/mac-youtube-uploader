import SwiftUI

struct UploadInspectorView: View {
    var job: UploadJob?
    @ObservedObject var channels: YouTubeChannelStore
    var onSave: (UploadJob.ID, UploadMetadata, String?, String?) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var tagsText = ""
    @State private var privacy: PrivacyStatus = .private
    @State private var categoryID = YouTubeCategory.defaults[0].id
    @State private var madeForKids = false
    @State private var allowEmbedding = true
    @State private var selectedChannelID: String?
    @State private var selectedPlaylistID: String?
    @State private var loadedJobID: UploadJob.ID?

    var body: some View {
        Group {
            if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(for: job)

                        inspectorField(title: "Title") {
                            TextField("Video title", text: $title)
                                .textFieldStyle(.plain)
                                .appInput()
                                .disabled(!job.phase.canEditBeforeUpload)
                        }

                        inspectorField(title: "Description") {
                            TextEditor(text: $description)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 96)
                                .appInput()
                                .disabled(!job.phase.canEditBeforeUpload)
                        }

                        inspectorField(title: "Publishing") {
                            VStack(spacing: 10) {
                                inspectorMenuRow(title: "Channel", value: selectedChannelTitle, isEnabled: job.phase.canEditBeforeUpload) {
                                    ForEach(channels.authorizedChannels) { channel in
                                        Button {
                                            selectedChannelID = channel.id
                                        } label: {
                                            Label(
                                                channel.displayName,
                                                systemImage: channel.id == selectedChannelID ? "checkmark" : "circle"
                                            )
                                        }
                                    }
                                }

                                inspectorMenuRow(title: "Playlist", value: selectedPlaylistTitle, isEnabled: job.phase.canEditBeforeUpload) {
                                    Button {
                                        selectedPlaylistID = nil
                                    } label: {
                                        Label("No playlist", systemImage: selectedPlaylistID == nil ? "checkmark" : "circle")
                                    }

                                    ForEach(selectedChannelPlaylists) { playlist in
                                        Button {
                                            selectedPlaylistID = playlist.id
                                        } label: {
                                            Label(
                                                playlist.title,
                                                systemImage: playlist.id == selectedPlaylistID ? "checkmark" : "circle"
                                            )
                                        }
                                    }
                                }

                                inspectorMenuRow(title: "Privacy", value: privacy.label, isEnabled: job.phase.canEditBeforeUpload) {
                                    ForEach(PrivacyStatus.allCases) { status in
                                        Button {
                                            privacy = status
                                        } label: {
                                            Label(status.label, systemImage: status == privacy ? "checkmark" : "circle")
                                        }
                                    }
                                }

                                inspectorMenuRow(title: "Category", value: selectedCategoryName, isEnabled: job.phase.canEditBeforeUpload) {
                                    ForEach(YouTubeCategory.defaults) { category in
                                        Button {
                                            categoryID = category.id
                                        } label: {
                                            Label(
                                                category.name,
                                                systemImage: category.id == selectedCategoryID ? "checkmark" : "circle"
                                            )
                                        }
                                    }
                                }

                                Toggle("Made for kids", isOn: $madeForKids)
                                    .toggleStyle(.checkbox)
                                    .disabled(!job.phase.canEditBeforeUpload)

                                Toggle("Allow embedding", isOn: $allowEmbedding)
                                    .toggleStyle(.checkbox)
                                    .disabled(!job.phase.canEditBeforeUpload)
                            }
                        }

                        inspectorField(title: "Tags") {
                            TextField("travel, vlog, 4k", text: $tagsText)
                                .textFieldStyle(.plain)
                                .appInput()
                                .disabled(!job.phase.canEditBeforeUpload)
                        }

                        if job.phase.canEditBeforeUpload {
                            if !canSave {
                                InspectorInlineMessage(message: "Enter a title before saving this upload.")
                            }

                            Button {
                                save(job)
                            } label: {
                                Label("Save Upload Details", systemImage: "checkmark")
                            }
                            .buttonStyle(PrimaryAppButtonStyle())
                            .disabled(!canSave)
                        } else {
                            InspectorInlineMessage(message: "Upload details are locked after processing starts.")
                        }
                    }
                    .padding(18)
                }
            } else {
                EmptyInspectorView()
            }
        }
        .background(AppTheme.surface)
        .onAppear {
            load(job)
        }
        .onChange(of: job?.id) { _, _ in
            load(job)
        }
        .onChange(of: selectedChannelID) { _, newChannelID in
            guard let newChannelID,
                  selectedPlaylistID.flatMap({ channels.playlist(id: $0, channelID: newChannelID) }) != nil else {
                selectedPlaylistID = nil
                return
            }
        }
    }

    private func header(for job: UploadJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload Details")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.text)

                    Text(job.phase.canEditBeforeUpload ? "Review before publishing." : job.phase.label)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                InspectorMetaLabel(text: job.sourceURLs.first?.lastPathComponent ?? job.titleSeed, icon: "doc")
                InspectorMetaLabel(text: job.totalSizeDescription, icon: "internaldrive")
                InspectorMetaLabel(text: "\(job.chunkCount) file\(job.chunkCount == 1 ? "" : "s")", icon: "film.stack")
            }
        }
        .appCard(padding: 12, background: AppTheme.field, border: AppTheme.line)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedChannelTitle: String {
        guard let selectedChannelID,
              let channel = channels.authorizedChannels.first(where: { $0.id == selectedChannelID }) else {
            return "No channel"
        }
        return channel.displayName
    }

    private var selectedChannelPlaylists: [YouTubePlaylist] {
        guard let selectedChannelID else { return [] }
        return channels.playlistsByChannelID[selectedChannelID] ?? []
    }

    private var selectedPlaylistTitle: String {
        guard let selectedPlaylistID,
              let selectedChannelID,
              let playlist = channels.playlist(id: selectedPlaylistID, channelID: selectedChannelID) else {
            return "No playlist"
        }
        return playlist.title
    }

    private var selectedCategoryID: String {
        YouTubeCategory.defaults.contains { $0.id == categoryID }
            ? categoryID
            : YouTubeCategory.defaults[0].id
    }

    private var selectedCategoryName: String {
        YouTubeCategory.name(for: selectedCategoryID)
    }

    private var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func load(_ job: UploadJob?) {
        guard loadedJobID != job?.id else { return }
        loadedJobID = job?.id

        guard let job else {
            title = ""
            description = ""
            tagsText = ""
            privacy = .private
            categoryID = YouTubeCategory.defaults[0].id
            madeForKids = false
            allowEmbedding = true
            selectedChannelID = nil
            selectedPlaylistID = nil
            return
        }

        title = job.metadata.title
        description = job.metadata.description
        tagsText = job.metadata.tags.joined(separator: ", ")
        privacy = job.metadata.privacy
        categoryID = job.metadata.categoryID
        madeForKids = job.metadata.madeForKids
        allowEmbedding = job.metadata.allowEmbedding
        selectedChannelID = job.selectedChannelID ?? channels.selectedChannelID
        selectedPlaylistID = job.selectedPlaylistID
    }

    private func save(_ job: UploadJob) {
        let metadata = UploadMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            tags: tags,
            categoryID: selectedCategoryID,
            privacy: privacy,
            madeForKids: madeForKids,
            allowEmbedding: allowEmbedding
        )
        onSave(job.id, metadata, selectedChannelID, selectedPlaylistID)
    }

    @ViewBuilder
    private func inspectorField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            content()
        }
        .appCard(padding: 14, background: AppTheme.surface, border: AppTheme.line, shadow: false)
    }

    @ViewBuilder
    private func inspectorMenuRow<MenuContent: View>(
        title: String,
        value: String,
        isEnabled: Bool,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)

                    Text(value)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct EmptyInspectorView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 62, height: 54)
                .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))

            Text("Select an upload")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.text)

            Text("Review title, privacy, channel, playlist, and metadata before publishing.")
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface)
    }
}

private struct InspectorMetaLabel: View {
    var text: String
    var icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
    }
}

private struct InspectorInlineMessage: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.red)
                .padding(.top, 2)

            Text(message)
                .font(.caption)
                .foregroundStyle(AppTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.redSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.red.opacity(0.25), lineWidth: 1)
        }
    }
}
