#!/bin/zsh

set -euo pipefail

app_path=${1:?"Usage: scripts/validate-release.sh /path/to/Mac YouTube Uploader.app"}
info_plist="$app_path/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
    print -u2 "Missing app Info.plist at $info_plist"
    exit 1
fi

client_id=$(/usr/libexec/PlistBuddy -c "Print :YouTubeOAuthClientID" "$info_plist" 2>/dev/null || true)
if [[ "$client_id" != *.apps.googleusercontent.com ]]; then
    print -u2 "Release app does not contain a usable Google OAuth client ID."
    exit 1
fi

client_secret=$(/usr/libexec/PlistBuddy -c "Print :YouTubeOAuthClientSecret" "$info_plist" 2>/dev/null || true)
if [[ -n "$client_secret" ]]; then
    print -u2 "Release app must not contain a Google OAuth client secret."
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

print "Release validation passed for $app_path"
