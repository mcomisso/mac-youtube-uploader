import AppKit
import SwiftUI

@main
struct MacYouTubeUploaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences: PreferencesStore
    @StateObject private var uploads: UploadStore

    init() {
        let preferences = PreferencesStore()
        let uploads = UploadStore(preferences: preferences)
        _preferences = StateObject(wrappedValue: preferences)
        _uploads = StateObject(wrappedValue: uploads)

        // Skipped while hosting unit tests, which stage fixture files in the
        // assembly directory. Assemblies still referenced by restored queue
        // jobs are kept so those jobs can retry or resume without remuxing.
        if NSClassFromString("XCTestCase") == nil {
            let referencedAssemblies = Set(uploads.jobs.compactMap(\.assembledFileURL))
            Task.detached(priority: .utility) {
                ChunkAssembler.removeLeftoverAssemblies(keeping: referencedAssemblies)
            }
        }
    }

    var body: some Scene {
        WindowGroup("Mac YouTube Uploader", id: AppSceneID.mainWindow) {
            ContentView(uploads: uploads, preferences: preferences, channels: preferences.channels)
                .frame(minWidth: 1180, minHeight: 700)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Videos...") {
                    uploads.chooseAndEnqueueFiles()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Start Queue") {
                    uploads.startQueuedUploads()
                }
                .keyboardShortcut("u", modifiers: [.command])
            }

            CommandMenu("Upload") {
                Button("Cancel Uploads") {
                    uploads.cancelAllCancellableJobs()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(uploads.cancellableCount == 0)

                Button("Clear Finished") {
                    uploads.clearFinishedJobs()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }

        Settings {
            SettingsView(preferences: preferences, channels: preferences.channels)
                .frame(width: 560, height: 520)
        }

        MenuBarExtra(isInserted: menuBarStatusBinding) {
            MenuBarUploadStatusView(uploads: uploads, preferences: preferences)
        } label: {
            MenuBarUploadIcon(activity: uploads.uploadActivityStatus)
        }
    }

    private var menuBarStatusBinding: Binding<Bool> {
        Binding {
            preferences.showsMenuBarIcon && uploads.uploadActivityStatus != nil
        } set: { isVisible in
            preferences.setShowsMenuBarIcon(isVisible)
        }
    }
}

enum AppSceneID {
    static let mainWindow = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
