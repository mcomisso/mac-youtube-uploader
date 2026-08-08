import Foundation

enum AppLegal {
    static let currentAgreementVersion = "2026-06-11"

    static let youTubeTermsURL = URL(string: "https://www.youtube.com/t/terms")!
    static let youTubeAPITermsURL = URL(string: "https://developers.google.com/youtube/terms/api-services-terms-of-service")!
    static let googlePrivacyURL = URL(string: "https://policies.google.com/privacy")!
    static let googlePermissionsURL = URL(string: "https://security.google.com/settings/security/permissions")!
    static let googleAPIUserDataPolicyURL = URL(string: "https://developers.google.com/terms/api-services-user-data-policy")!
}

enum LegalDocumentKind: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms and Conditions"
        }
    }

    var body: String {
        switch self {
        case .privacy:
            """
            Mac YouTube Uploader is a native macOS app for selecting local video files, preparing upload metadata, connecting a YouTube channel, and uploading videos through YouTube API Services.

            The app is designed to run locally on your Mac. It does not operate an app backend that receives your video files, YouTube tokens, upload metadata, or channel data.

            Information handled by the app includes video files and folders you select, upload metadata you enter, Google OAuth client details you configure, connected YouTube channel details, playlist metadata, and OAuth credentials needed to upload without signing in every time.

            The app requests the YouTube SSL write scope. This permission is used to list the YouTube channels and playlists available to your Google account, keep the selected channel connected, refresh credentials when needed, upload videos with the metadata you provide, and add uploaded videos to a selected playlist.

            OAuth credentials, manually entered OAuth client secrets, connected channel information, and downloaded playlist metadata are stored in the macOS Keychain. Metadata defaults and app preferences are stored in local macOS app preferences.

            Videos and related metadata are sent to YouTube only when you choose to upload them. YouTube and Google process that information under their own terms and privacy policies. The app does not intentionally share your local video files, OAuth tokens, channel details, or upload metadata with any other third party.

            Stored YouTube API data such as connected channel details and playlist metadata is refreshed or deleted after 30 days. You can delete locally stored YouTube data from Settings. You can also revoke the app's Google access from your Google account permissions page.

            Deleting data stored by Mac YouTube Uploader does not delete videos, playlists, or other data stored by YouTube. Videos already uploaded to YouTube must be managed in YouTube.

            The app is not directed to children under 13. Do not use the app if you are not old enough to manage a Google or YouTube account under the rules that apply to you.

            For privacy questions, contact the developer through the support, repository, or distribution channel where you received Mac YouTube Uploader.
            """
        case .terms:
            """
            By using Mac YouTube Uploader, you agree to these terms. If you do not agree, do not use the app.

            Mac YouTube Uploader helps you select local videos, reconstruct supported split camera recordings, apply upload metadata, connect a YouTube channel, and upload videos to YouTube through YouTube API Services.

            You are responsible for reviewing all files, channel selections, playlist selections, privacy settings, and metadata before uploading. You must own or have all rights and permissions needed to upload the videos, audio, images, titles, descriptions, tags, and other content you submit through the app.

            The app uses YouTube API Services. By using Mac YouTube Uploader with YouTube, you also agree to be bound by the YouTube Terms of Service, the YouTube API Services Terms of Service, applicable YouTube API Services policies, and Google's OAuth and API policies.

            You may revoke the app's Google account access at any time from your Google account permissions page. Revoking access may prevent uploads, channel selection, or playlist selection from working until you connect again.

            The app and website are provided as available. Upload behavior can depend on your Mac, network connection, selected files, Google OAuth configuration, YouTube API availability, quota limits, and YouTube account status. Features may change, break, or be discontinued.

            For questions about these terms, contact the developer through the support, repository, or distribution channel where you received Mac YouTube Uploader.
            """
        }
    }
}
