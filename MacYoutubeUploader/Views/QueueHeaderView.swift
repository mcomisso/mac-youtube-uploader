import SwiftUI

struct QueueHeaderView: View {
    @ObservedObject var uploads: UploadStore
    var filter: QueueFilter

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                QueueHeaderTitle(title: title, subtitle: subtitle)

                Spacer(minLength: 18)

                QueueHeaderActions(uploads: uploads)
            }

            VStack(alignment: .leading, spacing: 12) {
                QueueHeaderTitle(title: title, subtitle: subtitle)
                QueueHeaderActions(uploads: uploads)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 14, shadow: false)
    }

    private var title: String {
        if filter != .all {
            let count = filter.count(in: uploads.jobs)
            return count == 0 ? filter.title : "\(count) \(filter.title.lowercased())"
        }

        if uploads.jobs.isEmpty {
            return "Upload Queue"
        }

        if uploads.activeCount > 0 {
            return "Uploading \(uploads.activeCount) of \(uploads.jobs.count)"
        }

        if uploads.queuedCount > 0 {
            return "\(uploads.queuedCount) queued"
        }

        return "Upload Queue"
    }

    private var subtitle: String {
        if filter != .all {
            return "Showing uploads matching the \(filter.title.lowercased()) filter."
        }

        if let activity = uploads.uploadActivityStatus {
            return activity.detail
        }

        return "Drop split camera files together. Matching chunks are rebuilt before upload."
    }
}

private struct QueueHeaderTitle: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct QueueHeaderActions: View {
    @ObservedObject var uploads: UploadStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                openFilesButton
                combineFilesButton
                cancelButton
                startQueueButton
            }

            HStack(spacing: 10) {
                Menu {
                    Button("Open Files", systemImage: "plus") {
                        uploads.chooseAndEnqueueFiles()
                    }
                    Button("Combine Files", systemImage: "square.stack.3d.up") {
                        uploads.chooseAndEnqueueCombinedFiles()
                    }
                } label: {
                    Label("Add Videos", systemImage: "plus")
                }
                .buttonStyle(SecondaryAppButtonStyle())

                cancelButton
                startQueueButton
            }
        }
    }

    private var openFilesButton: some View {
        Button {
            uploads.chooseAndEnqueueFiles()
        } label: {
            Label("Open Files", systemImage: "plus")
        }
        .buttonStyle(SecondaryAppButtonStyle())
    }

    private var combineFilesButton: some View {
        Button {
            uploads.chooseAndEnqueueCombinedFiles()
        } label: {
            Label("Combine Files", systemImage: "square.stack.3d.up")
        }
        .buttonStyle(SecondaryAppButtonStyle())
    }

    @ViewBuilder
    private var cancelButton: some View {
        if uploads.cancellableCount > 0 {
            Button {
                uploads.cancelAllCancellableJobs()
            } label: {
                Label("Cancel", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(SecondaryAppButtonStyle())
        }
    }

    private var startQueueButton: some View {
        Button {
            uploads.startQueuedUploads()
        } label: {
            Label("Start Queue", systemImage: "play.fill")
        }
        .buttonStyle(PrimaryAppButtonStyle())
    }
}
