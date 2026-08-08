import SwiftUI

struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(2)
        }
        .background(AppTheme.background)
    }
}

struct SettingsHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 38, height: 38)
                .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: AppTheme.radius, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard(padding: 14, background: AppTheme.surface, border: AppTheme.line)
    }
}

struct SettingsCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 14, background: AppTheme.surface, border: AppTheme.line)
    }
}

struct LabeledSettingField<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            content
        }
    }
}

struct SettingsInlineMessage: View {
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
