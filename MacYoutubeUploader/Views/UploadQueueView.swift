import AppKit
import SwiftUI

struct UploadQueueView: View {
    @ObservedObject var uploads: UploadStore
    var filter: QueueFilter
    @Binding var selectedJobID: UploadJob.ID?

    var body: some View {
        Group {
            if filteredJobs.isEmpty {
                EmptyQueueView(filter: filter)
            } else {
                List(selection: $selectedJobID) {
                    ForEach(filteredJobs) { job in
                        UploadJobRow(
                            job: job,
                            isSelected: selectedJobID == job.id,
                            onCancel: {
                                uploads.cancel(jobID: job.id)
                            }
                        )
                        .tag(job.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            if job.phase.canCancel {
                                Button("Cancel Upload") {
                                    uploads.cancel(jobID: job.id)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredJobs: [UploadJob] {
        uploads.jobs.filter(filter.matches)
    }
}

private struct EmptyQueueView: View {
    var filter: QueueFilter

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .fill(AppTheme.blueSoft)

                Image(systemName: "film.stack")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppTheme.blue)
            }
            .frame(width: 68, height: 58)

            VStack(spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appCard(padding: 24, background: AppTheme.surface, border: AppTheme.line)
    }

    private var title: String {
        filter == .all ? "No videos queued" : "No \(filter.title.lowercased())"
    }

    private var message: String {
        filter == .all
            ? "Drag files into the drop area or use Open Files."
            : "Uploads matching this filter will appear here."
    }
}

private struct UploadJobRow: View {
    var job: UploadJob
    var isSelected: Bool
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 13) {
                JobThumbnail(job: job)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(job.metadata.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.text)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(job.phase.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(statusColor)

                        if job.phase.canCancel {
                            Button(action: onCancel) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .buttonStyle(.plain)
                            .help("Cancel job")
                            .accessibilityLabel("Cancel \(job.metadata.title)")
                        }
                    }

                    JobDetailView(job: job)

                    if shouldShowProgress || job.phase.isTerminal {
                        HStack(spacing: 10) {
                            LinearUploadProgressView(
                                value: progressValue,
                                tint: statusColor,
                                sparkles: job.phase.isUploading,
                                accessibilityLabelText: progressAccessibilityLabel
                            )

                            Text("\(Int((progressValue * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.muted)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }

                    HStack(spacing: 12) {
                        QueueMetaLabel(text: "\(job.chunkCount) file\(job.chunkCount == 1 ? "" : "s")", icon: "doc")
                        QueueMetaLabel(text: job.totalSizeDescription, icon: "internaldrive")
                        QueueMetaLabel(text: job.metadata.privacy.label, icon: "eye")
                    }
                }
            }

            if job.chunkCount > 1 {
                ChunkListView(job: job)
            }
        }
        .appCard(
            padding: 14,
            background: isSelected ? AppTheme.blueSoft : AppTheme.surface,
            border: isSelected ? AppTheme.blue.opacity(0.35) : AppTheme.line,
            shadow: false
        )
    }

    private var shouldShowProgress: Bool {
        job.phase.isActive
    }

    private var progressValue: Double {
        switch job.phase {
        case .completed:
            return 1
        case .failed:
            return min(max(job.progress, 0), 1)
        case .queued, .waitingForAccount, .cancelled:
            return 0
        case .reconstructing, .uploading:
            return min(max(job.progress, 0), 1)
        default:
            return min(max(job.progress, 0.08), 1)
        }
    }

    private var progressAccessibilityLabel: String {
        switch job.phase {
        case .reconstructing:
            return "Remux progress"
        case .uploading:
            return "Upload progress"
        default:
            return "Job progress"
        }
    }

    private var statusColor: Color {
        switch job.phase {
        case .completed: AppTheme.green
        case .failed: AppTheme.red
        case .waitingForAccount, .interrupted: AppTheme.orange
        case .uploading, .reconstructing, .preparing: AppTheme.blue
        case .queued, .cancelled: AppTheme.muted
        }
    }
}

private struct JobDetailView: View {
    var job: UploadJob

    var body: some View {
        if let videoURL = job.publishedVideoURL {
            Link(destination: videoURL) {
                Text(job.detail)
                    .font(.callout)
                    .foregroundStyle(AppTheme.blue)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help(videoURL.absoluteString)
            .accessibilityLabel("Open published YouTube video")
            .accessibilityValue(videoURL.absoluteString)
        } else {
            Text(job.detail)
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
    }
}

private struct JobThumbnail: View {
    var job: UploadJob

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false

    private static let thumbnailGenerator = VideoThumbnailGenerator()
    private let thumbnailPixelSize = CGSize(width: 240, height: 150)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            thumbnailContent

            if thumbnail != nil {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.56)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            Text(job.chunkCount > 1 ? "\(job.chunkCount) chunks" : "video")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(6)
        }
        .frame(width: 96, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.line.opacity(0.8), lineWidth: 1)
        }
        .task(id: thumbnailTaskID) {
            await loadThumbnail(from: thumbnailURLs)
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 58)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0x183A59),
                        Color(hex: 0x6CA6D8),
                        Color(hex: 0xE7C28B)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if isLoadingThumbnail {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private var iconName: String {
        job.chunkCount > 1 ? "puzzlepiece.extension" : "play.rectangle.fill"
    }

    private var thumbnailURLs: [URL] {
        if let assembledFileURL = job.assembledFileURL {
            return [assembledFileURL] + job.sourceURLs
        }
        return job.sourceURLs
    }

    private var thumbnailTaskID: String {
        thumbnailURLs
            .map { $0.standardizedFileURL.path }
            .joined(separator: "|")
    }

    @MainActor
    private func loadThumbnail(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        isLoadingThumbnail = thumbnail == nil
        let image = await Self.thumbnailGenerator.thumbnail(for: urls, maximumSize: thumbnailPixelSize)
        guard !Task.isCancelled else { return }

        thumbnail = image
        isLoadingThumbnail = false
    }
}

private struct QueueMetaLabel: View {
    var text: String
    var icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
    }
}

private struct ChunkListView: View {
    var job: UploadJob

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(job.sourceURLs.prefix(8).enumerated()), id: \.element.path) { index, url in
                ChunkFileRow(
                    url: url,
                    state: state(for: index)
                )

                if index < min(job.sourceURLs.count, 8) - 1 {
                    AppDivider(axis: .horizontal)
                        .padding(.leading, 26)
                }
            }

            if job.sourceURLs.count > 8 {
                HStack {
                    Text("...and \(job.sourceURLs.count - 8) more")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
        }
        .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        }
    }

    private func state(for index: Int) -> ChunkFileState {
        switch job.phase {
        case .completed:
            return .complete
        case .failed:
            return .failed
        case .cancelled:
            return .pending
        case .uploading:
            return .complete
        case .reconstructing:
            let completedIndex = Int((job.progress * Double(job.sourceURLs.count)).rounded(.down))
            if index < completedIndex {
                return .complete
            }
            if index == completedIndex {
                return .active(progress: job.progress)
            }
            return .pending
        case .preparing:
            return index == 0 ? .active(progress: 0) : .pending
        default:
            return .pending
        }
    }
}

private enum ChunkFileState {
    case pending
    case active(progress: Double)
    case complete
    case failed
}

private struct ChunkFileRow: View {
    var url: URL
    var state: ChunkFileState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .frame(width: 16)

            Text(url.lastPathComponent)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let size = url.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            ChunkStateIcon(state: state)
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
    }
}

private struct ChunkStateIcon: View {
    var state: ChunkFileState

    var body: some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppTheme.red)
        case .active:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .pending:
            Circle()
                .stroke(AppTheme.line, lineWidth: 1.5)
                .frame(width: 14, height: 14)
        }
    }
}
