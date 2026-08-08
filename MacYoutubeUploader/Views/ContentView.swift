import SwiftUI

struct ContentView: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var channels: YouTubeChannelStore
    @State private var selectedFilter: QueueFilter? = .all
    @State private var selectedJobID: UploadJob.ID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                uploads: uploads,
                preferences: preferences,
                channels: channels,
                selection: $selectedFilter
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            MainWorkspaceView(
                uploads: uploads,
                preferences: preferences,
                channels: channels,
                filter: activeFilter,
                selectedJobID: $selectedJobID,
                job: selectedJob,
                onSave: updateJobMetadata
            )
        }
        .navigationSplitViewStyle(.balanced)
        .background(AppTheme.background)
        .alert("Upload Error", isPresented: errorBinding) {
            Button("OK") {
                uploads.clearError()
                channels.clearError()
            }
        } message: {
            Text(uploads.errorMessage ?? channels.errorMessage ?? "")
        }
        .onAppear {
            normalizeSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            normalizeSelection()
        }
        .onChange(of: uploads.jobs) { _, _ in
            normalizeSelection()
        }
    }

    private var activeFilter: QueueFilter {
        selectedFilter ?? .all
    }

    private var filteredJobs: [UploadJob] {
        uploads.jobs.filter(activeFilter.matches)
    }

    private var selectedJob: UploadJob? {
        guard let selectedJobID else { return nil }
        return uploads.jobs.first { $0.id == selectedJobID }
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            uploads.errorMessage != nil || channels.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                uploads.clearError()
                channels.clearError()
            }
        }
    }

    private func normalizeSelection() {
        if selectedFilter == nil {
            selectedFilter = .all
        }

        if let selectedJobID,
           filteredJobs.contains(where: { $0.id == selectedJobID }) {
            return
        }

        selectedJobID = filteredJobs.first?.id
    }

    private func updateJobMetadata(
        jobID: UploadJob.ID,
        metadata: UploadMetadata,
        channelID: String?,
        playlistID: String?
    ) {
        uploads.updateJob(
            id: jobID,
            metadata: metadata,
            selectedChannelID: channelID,
            selectedPlaylistID: playlistID
        )
    }
}

private struct MainWorkspaceView: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var channels: YouTubeChannelStore
    var filter: QueueFilter
    @Binding var selectedJobID: UploadJob.ID?
    var job: UploadJob?
    var onSave: (UploadJob.ID, UploadMetadata, String?, String?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            QueueWorkspaceColumn(
                uploads: uploads,
                preferences: preferences,
                filter: filter,
                selectedJobID: $selectedJobID
            )
            .frame(minWidth: 480, maxWidth: .infinity)
            .layoutPriority(1)

            AppDivider(axis: .vertical)

            UploadInspectorView(
                job: job,
                channels: channels,
                onSave: onSave
            )
            .frame(minWidth: 420, idealWidth: 500, maxWidth: 560, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}

private struct QueueWorkspaceColumn: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore
    var filter: QueueFilter
    @Binding var selectedJobID: UploadJob.ID?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                QueueHeaderView(uploads: uploads, filter: filter)
                if uploads.showsInterruptedUploadsPrompt, uploads.interruptedCount > 0 {
                    InterruptedUploadsBanner(
                        count: uploads.interruptedCount,
                        onResume: { uploads.resumeInterruptedUploads() },
                        onDismiss: { uploads.dismissInterruptedUploadsPrompt() }
                    )
                }
                DropZoneView(uploads: uploads)
                UploadQueueView(
                    uploads: uploads,
                    filter: filter,
                    selectedJobID: $selectedJobID
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            AppStatusBarView(uploads: uploads, preferences: preferences)
        }
        .background(AppTheme.background)
    }
}

private struct AppStatusBarView: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        VStack(spacing: 0) {
            AppDivider(axis: .horizontal)

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text(statusTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }

                    Text(statusTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                }

                Image(systemName: preferences.keepMacAwake ? "moon.zzz" : "moon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(AppTheme.surface)
        }
    }

    private var statusColor: Color {
        uploads.activeCount > 0 ? AppTheme.blue : AppTheme.green
    }

    private var statusTitle: String {
        uploads.activeCount > 0 ? "\(uploads.activeCount) upload\(uploads.activeCount == 1 ? "" : "s") active" : "Background uploads are enabled"
    }

    private var statusDetail: String {
        preferences.keepMacAwake ? "Uploads keep the Mac awake while active" : "Uploads continue while the Mac is awake"
    }
}
