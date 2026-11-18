# Environments

| Environment | Firebase project file | How it is selected |
|---|---|---|
| development | `Config/GoogleService-Info-Dev.plist` (falls back to the default file with a warning) | Debug build setting `MB_ENVIRONMENT = development` |
| staging | `Config/GoogleService-Info-Staging.plist` (**required**; app aborts at launch without it) | a "Staging" build configuration, or the scheme variable below (DEBUG only) |
| production | `GoogleService-Info.plist` | Release build setting `MB_ENVIRONMENT = production` |
| test | none (mock backend) | launch environment `MBUITesting=1` |

`MB_ENVIRONMENT` is expanded into Info.plist key `MBEnvironment` and read by `AppConfiguration.current()`.

## Running against another environment from Xcode (DEBUG builds only)
Edit Scheme → Run → Arguments → Environment Variables:
- `MBEnvironment = staging` (or `development` / `production`)
- `MBFirebaseEmulatorHost = localhost` (development only; use your Mac's LAN IP on a physical device)
Release builds ignore both variables, so a shipped binary cannot be redirected.

## Creating a Staging build configuration (one-time, in Xcode)
1. Project → Info → Configurations → duplicate **Release** → name it `Staging`.
2. App target → Build Settings → add user-defined `MB_ENVIRONMENT = staging` for `Staging` only.
3. Duplicate the MyBuddy scheme → set Archive/Run build configuration to `Staging`.
4. Use a different bundle identifier suffix (e.g. `.staging`) and register that iOS app in the staging Firebase project; its
   `GoogleService-Info-Staging.plist` goes in `ios/MyBuddy/Config/`.

## Emulators
```
cd firebase
firebase emulators:start      # auth 9099, firestore 8080, storage 9199, functions 5001, UI 4000
```
`firebase.json` points at the *proposed* rules, so the emulator is where they get exercised. Do not deploy them to production
before rules unit tests pass (none are written yet).

## Notes
- The Firebase API key in `GoogleService-Info.plist` is an identifier, not a secret, but restrict it in Google Cloud Console
  (Credentials → API key → Application restrictions → iOS bundle IDs) and enable App Check before launch.
- `firestore.indexes.json` declares the one composite index the app needs (`chats`: `participants` array-contains + `updatedAt`
  descending). Other queries use single-field indexes.
