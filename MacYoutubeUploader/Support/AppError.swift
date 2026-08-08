import Foundation

enum AppError: LocalizedError {
    case missingOAuthClientID
    case oauthBrowserLaunchFailed
    case oauthStateMismatch
    case oauthDenied(String)
    case legalAgreementRequired
    case missingRefreshToken
    case noYouTubeChannel
    case noSelectedChannel
    case missingUploadLocation
    case invalidHTTPStatus(Int, String)
    case exportUnavailable
    case exportFailed(String)
    case keychain(OSStatus)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingOAuthClientID:
            "Enter a Google OAuth desktop client ID in settings first."
        case .oauthBrowserLaunchFailed:
            "Google sign-in could not open in your web browser. Check your default browser and try again."
        case .oauthStateMismatch:
            "Google sign-in returned an unexpected state value. Try connecting again."
        case .oauthDenied(let message):
            "Google sign-in was denied: \(message)"
        case .legalAgreementRequired:
            "Accept the privacy policy and terms before connecting YouTube or uploading."
        case .missingRefreshToken:
            "Google did not return a refresh token. Reconnect the channel and approve offline access."
        case .noYouTubeChannel:
            "No YouTube channel was returned for this Google account."
        case .noSelectedChannel:
            "Select or connect a YouTube channel before uploading."
        case .missingUploadLocation:
            "YouTube did not return a resumable upload URL."
        case .invalidHTTPStatus(let status, let body):
            "YouTube returned HTTP \(status). \(body)"
        case .exportUnavailable:
            "macOS could not create an AVFoundation export session for these chunks."
        case .exportFailed(let message):
            "Video reconstruction failed: \(message)"
        case .keychain(let status):
            "Keychain returned status \(status)."
        case .server(let message):
            message
        }
    }
}
