import AppKit
import SwiftUI

struct MenuBarUploadStatusView: View {
    @ObservedObject var uploads: UploadStore
    @ObservedObject var preferences: PreferencesStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let activity = uploads.uploadActivityStatus {
            Section {
                Text(activity.shortTitle)
                Text(activity.detail)

                if activity.isUploading {
                    Text("\(activity.percentUploaded)% uploaded")
                    ProgressView(value: activity.progress)
                } else {
                    ProgressView()
                }
            }
        } else {
            Text("No active uploads")
        }

        Divider()

        Button("Open App") {
            openMainWindow()
        }

        Button("Add Videos...") {
            openMainWindow()
            uploads.chooseAndEnqueueFiles()
        }

        Button("Start Queue") {
            uploads.startQueuedUploads()
        }

        if uploads.cancellableCount > 0 {
            Button("Cancel Uploads") {
                uploads.cancelAllCancellableJobs()
            }
        }

        Divider()

        SettingsLink {
            Text("Settings")
        }

        Toggle("Show During Uploads", isOn: menuBarIconBinding)

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMainWindow() {
        if let existingWindow = NSApp.windows.first(where: { $0.title == "Mac YouTube Uploader" }) {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: AppSceneID.mainWindow)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private var menuBarIconBinding: Binding<Bool> {
        Binding {
            preferences.showsMenuBarIcon
        } set: { isVisible in
            preferences.setShowsMenuBarIcon(isVisible)
        }
    }
}

struct MenuBarUploadIcon: View {
    var activity: UploadActivityStatus?

    var body: some View {
        ZStack {
            if let activity, activity.isUploading {
                Circle()
                    .stroke(.secondary.opacity(0.35), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: activity.progress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
            } else if activity != nil {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let activity else {
            return "Upload status"
        }

        if activity.isUploading {
            return "Uploading \(activity.percentUploaded)%"
        }

        return "Uploads active"
    }
}
