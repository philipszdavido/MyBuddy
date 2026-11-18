# MyBuddy handoff (read this first)

**Status:** large refactor written across 11 tranches. **Nothing has been compiled, run, or tested** (no Swift toolchain or
Firebase emulator was available). Expect compile errors on the first build.

## Do these in order
1. **Rotate the Cloudinary API secret** (it is in git history) and disable the unsigned preset `chat_uploads`.
2. Open `ios/MyBuddy.xcodeproj`, build, and send the full list of errors back. Fix pass follows.
3. Run unit tests (`MyBuddyTests`, ~70, all against mocks) and UI tests (`MyBuddyUITests`, 5 flows on the mock backend) and send failures.
4. Run the rules tests: `cd firebase/rules-tests && npm install && npm test` (needs Firebase CLI). Send failures.
5. Migration check: install your *current* App Store/TestFlight build, send a message, install this build over it, confirm
   chats and messages survive (Core Data model v1 -> v2 is lightweight but unproven).
6. Deploy only after step 4 passes: rules (`firebase/*.rules.proposed`), indexes, and functions (`firebase/functions`).
7. Manual setup: Push Notifications capability, APNs key in Firebase, `GoogleService-Info-Staging.plist`, real Terms/Privacy/
   Support URLs in Info.plist, App Check, restrict the Firebase API key, opaque (no-alpha) app icon.

## What exists (all unverified)
Architecture (Core / Domain / Data / Composition), backend abstraction (Firebase + mock), auth (reauth, reset, deletion),
chat (atomic idempotent send, outbox, bounded listeners, paging, failed state), feed (own-feed listener, reactions),
media (resize, Firebase Storage), push + deep links, environments + emulator support, report/block, privacy manifest,
String Catalog, accessibility labels, docs (`docs/`), rules + rules tests.

## Known gaps (not done)
- Server side: account-data deletion, feed fan-out, moderation of reports. Account deletion currently removes only the Auth user.
- Phone numbers are unverified identity; chat IDs embed phone numbers; `users/{uid}` (with email) readable by any signed-in user.
- UI tests cover only auth/delete/blocked-users (none for chat, feed, offline); no profiling; no full VoiceOver/Dynamic Type pass; localization is English only.
- Upload progress UI, video, background uploads. AI Buddy is compiled out (`AI_BUDDY` flag).
- Behaviour changes to know about: logout is async; logout still clears the local cache (unsent messages lost); Cloudinary
  deletion removed; non-image media no longer cached; permission prompt for notifications appears after sign-in.

## Where things are
`docs/ios/ARCHITECTURE.md`, `docs/ios/ENVIRONMENTS.md`, `docs/ios/SECURITY_AND_APPSTORE_AUDIT.md`, `MyBuddy_AUDIT.md` (original audit),
`firebase/` (rules, indexes, emulator config, functions draft, rules tests).
