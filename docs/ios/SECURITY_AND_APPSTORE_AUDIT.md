# Security and App Store readiness audit

Method: code and configuration review plus grep scans of this repository. **Nothing was built or run, no Firebase project was
touched, and the rules/functions below were never executed against the emulator.** "Done" means written in code, not verified.

## Release blockers (you must act; I cannot)
| # | Item | Why it blocks |
|---|---|---|
| 1 | Rotate the Cloudinary API secret and purge it from git history | It was committed; treat as compromised |
| 2 | Disable the unsigned Cloudinary preset `chat_uploads` | Anyone can upload to your account |
| 3 | Test (emulator) then deploy `firestore.rules.proposed` / `storage.rules.proposed` | Without rules the backend has no authorization; the app currently relies on whatever is deployed (unknown to me) |
| 4 | Deploy server-side functions: push on new message (draft exists), feed fan-out, **account-data deletion** | Account deletion currently removes only the Auth user (App Store 5.1.1(v) needs the data removed) |
| 5 | Real Terms of Service, Privacy Policy and Support URLs in Info.plist (`MBTermsURL`, `MBPrivacyPolicyURL`, `MBSupportURL`) | Links are hidden while empty; App Store requires a privacy policy URL |
| 6 | Moderation process for user reports (`reports` collection) with a response SLA | Guideline 1.2 (user-generated content) |
| 7 | Add the Push Notifications capability, APNs key in Firebase | Push does not work otherwise |
| 8 | Phone numbers are unverified identity (no SMS/OTP) | Anyone can claim any number and receive that person's feed/contact matches |
| 9 | Enable App Check and restrict the Firebase API key by bundle ID | Abuse protection |
| 10 | App icon: remove the alpha channel (see findings) | Upload validation fails otherwise |
| 11 | App Store Connect: privacy "nutrition label", age rating (UGC), export compliance answer | Must match the app's real behaviour |

## Implemented in code (unverified)
- Secrets: `Secrets.swift` removed; no keys left in Swift sources (a placeholder OpenAI key was empty; AI Buddy is unreachable and now compiled out behind `AI_BUDDY`).
- Rules tests: `firebase/rules-tests/` has 18 emulator tests (membership, sender spoofing, block enforcement, reports, push tokens, feed, reactions). **Never run.** Writing them found a real bug in my own first rules: an idempotent message retry is an update by the sender, which the rules rejected, so the outbox would have marked a delivered message as failed. A sender-retry rule was added; the tests cover it.
- Authorization design: proposed rules cover users, chats, messages (membership, sender == caller, recipient may only flip
  `seen`, **blocked senders rejected**), feed copies, reactions, push tokens, blocks, reports, and Storage paths/size/type.
- User safety: report + block from the chat header, blocked-users list with unblock in Settings, blocked users hidden from chat
  list and feed, server-side rejection of their messages (rule).
- Logging: all `print` replaced by `debugLog` (compiled out of release) or `os.Logger` with privacy defaults; no tokens,
  passwords or message bodies are logged.
- Input handling: deep links strictly validated; user-supplied links only open if `http(s)`; two force-unwrap crashes on
  malformed URLs and a force cast removed; media downloads are HTTPS-only, status-checked and size-bounded.
- Privacy manifest `Config/PrivacyInfo.xcprivacy` (no tracking; collected: email, name, phone, contacts, photos, user content,
  user ID, device ID; required-reason API: UserDefaults CA92.1). **Declared from my reading of this code only**; compare with the
  Firebase SDK manifests and what App Store Connect will ask. I did not audit every system API call for other required-reason APIs.
- Permission strings rewritten (camera, photos, microphone, contacts). Check the contacts wording: the app queries Firestore with
  address-book phone numbers; confirm the "not stored" claim is true for your backend and logs.
- Dead code that wrote fake contacts into the device address book removed.

## Findings not fixed
- Chat IDs are derived from both phone numbers (visible in deep links, push payloads, Firestore paths).
- `users/{uid}` (including email) is readable by any signed-in user so contact matching works. Move email to a private subdocument.
- Contacts permission is requested when the app launches, before sign-in, which is poor UX and a review risk; request it in context.
- Feed fan-out and likes are still client-driven; reactions are per-user documents but a malicious client can still spam copies.
- `Persistence.preview`, `Mock.swift` and Lorem-ipsum preview data still compile into release (previews only; not shown to users).
- Deployment targets differ (17.2 project, 17.6 app); `ITSAppUsesNonExemptEncryption` is not set.
- **App icon has real transparency** (alpha 0-255 in `AppIcon.appiconset`); App Store Connect rejects icons with an alpha channel. I did not replace it because flattening picks a background colour for you. About 87% of its pixels are transparent: the artwork is a small rounded square floating on an empty canvas, so flattening it onto white looks unfinished (preview provided). Re-export it as a full-bleed square with an opaque background (iOS rounds the corners itself); re-export your icon without alpha before upload.
- Accessibility: every icon-only button in chat, camera, media and header now has a VoiceOver label, the input-bar camera icon is a real Button (was a tap gesture), and two no-op camera buttons were removed. No full VoiceOver, Dynamic Type or contrast pass was done on a device.
- Localization: SwiftUI literals (`Text("...")`, `Button("...")`, labels) are already localizable; String-typed messages now use `String(localized:)` and `Config/Localizable.xcstrings` holds those keys (en only, likes/dislikes have plural variants). No translations exist yet; Xcode will add the remaining literals to the catalog on build. Dates use locale-aware `.formatted`.
- Tests: ~60 unit tests written against mocks; **none have been run**. 5 UI tests exist (`MyBuddyUITests`: register, logout, wrong password, delete account, blocked-users empty state; mock backend via `MBUITesting=1`) but have never been run, and chat/feed/offline flows have no UI tests. Firebase repositories and the outbox
  retrier are untested.

## Not verified at all (no environment for it)
Build/compile, unit and UI tests, Instruments profiling, real push delivery, deep links from cold launch on a device, Core Data
v1→v2 migration on a real store, emulator behaviour of the rules and functions, App Store Connect validation.
