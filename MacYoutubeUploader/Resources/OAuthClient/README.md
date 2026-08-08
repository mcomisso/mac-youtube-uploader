# OAuth Client

Place a Google OAuth desktop client JSON file here as `client_secret.json` only for local development.

The simplest persistent option is the Import Client JSON button in the app's YouTube
settings, which stores the client ID and secret so sign-in works on every launch. The app
can also load this file from the source tree during local development, or you can set
`YOUTUBE_OAUTH_CLIENT_ID`, set `YOUTUBE_OAUTH_CLIENT_JSON` to another Google OAuth JSON
path, or paste the client ID and optional client secret in the app's YouTube settings.

Do not commit `client_secret.json`, and do not embed a real copy in distributed app builds.
