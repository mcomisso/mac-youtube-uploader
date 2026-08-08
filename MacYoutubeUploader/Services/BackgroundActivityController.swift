import Foundation

final class BackgroundActivityController {
    private var activity: NSObjectProtocol?

    func begin(keepMacAwake: Bool) {
        guard keepMacAwake, activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Uploading videos to YouTube"
        )
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
