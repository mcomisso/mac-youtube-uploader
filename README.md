# Mac YouTube Uploader

Mac YouTube Uploader is a native macOS app for queueing local videos, applying reusable metadata, reconstructing split camera recordings, and publishing through the YouTube Data API.

Use **Open Files** or drag files into the app to queue separate videos. Matching camera chunks are detected and reconstructed as one video. Use **Combine Files** to select two or more videos to publish as one video. The app combines those files in filename order, so name them in playback order before selecting them. Files in one combined video need compatible orientation and dimensions.

## Download

Download the latest notarized release from [GitHub Releases](https://github.com/mcomisso/mac-youtube-uploader/releases/latest).

The current release requires macOS 26.5 or later. After downloading, unzip the archive and move Mac YouTube Uploader to the Applications folder.

## YouTube setup

The app includes its public Google OAuth desktop client ID, uses OAuth with PKCE, and stores connected-channel credentials in the macOS Keychain. Accept the privacy policy and terms, then choose Sign in with Google.

The Expert setting can import a separate **Desktop app** OAuth client JSON file when you want to use your own Google Cloud project and YouTube API quota. Enable YouTube Data API v3 in that project and configure its OAuth consent screen. Existing connected channels keep their original OAuth client until you disconnect and reconnect them. [Google restricts uploads from unverified API projects created after July 28, 2020 to private viewing](https://developers.google.com/youtube/v3/revision_history).

Never commit or distribute a `client_secret.json` file with the app. The local OAuth client configuration path is ignored by git.

## Build

```bash
xcodebuild \
  -project MacYoutubeUploader.xcodeproj \
  -scheme MacYoutubeUploader \
  -configuration Debug \
  build
```

## Test

```bash
xcodebuild test \
  -project MacYoutubeUploader.xcodeproj \
  -scheme MacYoutubeUploader \
  -destination 'platform=macOS'
```

## Privacy

The app selects local files only when requested, stores upload preferences locally, and stores OAuth credentials in the macOS Keychain. See the [privacy policy](https://www.mac-youtube-uploader.com/privacy) and [terms](https://www.mac-youtube-uploader.com/terms).
