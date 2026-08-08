import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @ObservedObject var uploads: UploadStore
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                    .fill(isTargeted ? AppTheme.blue : AppTheme.blueSoft)

                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(isTargeted ? .white : AppTheme.blue)
            }
            .frame(width: 62, height: 54)

            Text("Drop files or folders")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.text)
                .lineLimit(1)

            Text("Camera chunks are detected and merged before they enter the queue.")
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .frame(minHeight: 154)
        .background(isTargeted ? AppTheme.blueSoft : AppTheme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous)
                .stroke(
                    isTargeted ? AppTheme.blue : AppTheme.dropBorder,
                    style: StrokeStyle(lineWidth: 1.4, dash: [8, 6])
                )
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await FileDropDecoder.urls(from: providers)
                await MainActor.run {
                    uploads.enqueue(urls)
                }
            }
            return true
        }
    }
}
