import SwiftUI

/// Shown at the top of the queue after a launch that restored uploads which
/// were mid-flight when the app last quit.
struct InterruptedUploadsBanner: View {
    var count: Int
    var onResume: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                bannerTitle

                Spacer(minLength: 18)

                bannerActions
            }

            VStack(alignment: .leading, spacing: 12) {
                bannerTitle
                bannerActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 14, shadow: false)
    }

    private var bannerTitle: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.up.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 upload was interrupted" : "\(count) uploads were interrupted")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Text("The app quit while uploading. Resume to continue from where YouTube left off.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bannerActions: some View {
        HStack(spacing: 10) {
            Button("Dismiss", action: onDismiss)
                .buttonStyle(SecondaryAppButtonStyle())

            Button(action: onResume) {
                Label(count == 1 ? "Resume Upload" : "Resume \(count) Uploads", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryAppButtonStyle())
        }
    }
}
