import SwiftUI

struct LegalConsentSettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @Binding var presentedDocument: LegalDocumentKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if preferences.hasAcceptedRequiredPolicies {
                Label("Accepted for this app version", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
            } else {
                SettingsInlineMessage(message: AppError.legalAgreementRequired.localizedDescription)
            }

            Text("YouTube features use YouTube API Services. Review the privacy policy and terms before connecting a Google account.")
                .font(.callout)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Privacy") {
                    presentedDocument = .privacy
                }
                .buttonStyle(SecondaryAppButtonStyle())

                Button("Terms") {
                    presentedDocument = .terms
                }
                .buttonStyle(SecondaryAppButtonStyle())

                Link("YouTube Terms", destination: AppLegal.youTubeTermsURL)
                    .buttonStyle(SecondaryAppButtonStyle())

                Link("Google Privacy", destination: AppLegal.googlePrivacyURL)
                    .buttonStyle(SecondaryAppButtonStyle())
            }

            Button {
                preferences.acceptRequiredPolicies()
            } label: {
                Label(
                    preferences.hasAcceptedRequiredPolicies ? "Accepted" : "Accept Privacy & Terms",
                    systemImage: preferences.hasAcceptedRequiredPolicies ? "checkmark" : "checkmark.circle"
                )
            }
            .buttonStyle(PrimaryAppButtonStyle())
            .disabled(preferences.hasAcceptedRequiredPolicies)
        }
    }
}

struct LegalPolicySheet: View {
    var document: LegalDocumentKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(document.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(SecondaryAppButtonStyle())
            }
            .padding(18)

            AppDivider(axis: .horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(document.body)
                        .font(.body)
                        .foregroundStyle(AppTheme.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Link("YouTube Terms of Service", destination: AppLegal.youTubeTermsURL)
                        Link("YouTube API Services Terms of Service", destination: AppLegal.youTubeAPITermsURL)
                        Link("Google Privacy Policy", destination: AppLegal.googlePrivacyURL)
                        Link("Google Account Permissions", destination: AppLegal.googlePermissionsURL)
                        Link("Google API Services User Data Policy", destination: AppLegal.googleAPIUserDataPolicyURL)
                    }
                    .font(.callout.weight(.semibold))
                }
                .padding(18)
            }
        }
        .frame(width: 560, height: 560)
        .background(AppTheme.background)
    }
}
