# Mac YouTube Uploader

Mac YouTube Uploader is a native macOS app for queueing local videos, applying reusable metadata, reconstructing split camera recordings, and publishing through the YouTube Data API.

## Download

Download the latest notarized release from [GitHub Releases](https://github.com/mcomisso/mac-youtube-uploader/releases/latest).

The current release requires macOS 26.5 or later. After downloading, unzip the archive and move Mac YouTube Uploader to the Applications folder.

## YouTube setup

The app uses Google OAuth with PKCE and stores connected-channel credentials in the macOS Keychain. Import a Google OAuth desktop client JSON file from Settings before connecting a YouTube channel.

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
