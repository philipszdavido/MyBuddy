Per-environment Firebase configuration files go in this folder (it is a synchronized Xcode group, so
files dropped here are bundled automatically):

  GoogleService-Info-Dev.plist       development Firebase project (optional: falls back to the default file with a warning)
  GoogleService-Info-Staging.plist   staging Firebase project (REQUIRED for staging builds; the app refuses to start without it)

Production uses MyBuddy/GoogleService-Info.plist. See docs/ENVIRONMENTS.md.
