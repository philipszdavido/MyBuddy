# MyBuddy architecture

```
Views ──▶ ViewModels / services ──▶ Domain protocols ──▶ Data/<backend>
                                     (Domain/)            (Data/Firebase, Data/Mock)
Composition/AppContainer picks the backend. Nothing else may.
```

| Folder | Role | May import Firebase? |
|---|---|---|
| `Core/` | `AppConfiguration`, `AppError`, `Log` | no |
| `Domain/` | models + `AuthenticationService`, `UserRepository`, `ChatRepository` | **no** |
| `Data/Firebase` | Firebase implementations + error mapping | yes |
| `Data/Mock` | in-memory fakes (tests, previews, `MBUITesting=1`) | no |
| `Composition/` | `AppContainer` (only place that selects a backend) | yes |
| legacy folders (`views`, `models`, `utils`, `listeners`, …) | migrating | see "Migration status" |

## Environments / backends
`AppConfiguration.current()` reads Info.plist key `MBEnvironment` (`development|staging|production`) and the launch
environment variable `MBUITesting=1` (mock backend). Staging/production Firebase projects still need separate
`GoogleService-Info-<env>.plist` files and build configurations (not done yet).

## Chat data flow
- **Send:** optimistic Core Data row (`sent == false`) → `ChatRepository.send` (one atomic batch, client-generated
  message id ⇒ idempotent) → on success `sent = true`. On failure the row stays pending and `OutboxRetrier`
  re-sends on app foreground and on connectivity return.
- **Receive:** `ChatSyncService` consumes bounded streams (latest 50 messages / 100 conversations) inside SwiftUI
  `.task`, so the Firestore listener is removed when the view disappears.
- **History:** `ChatRepository.loadOlderMessages` provides cursor pagination; the UI trigger is not wired yet.

## Replacing Firebase
Implement `AuthenticationService`, `UserRepository`, `ChatRepository` (e.g. `RESTChatRepository` over URLSession +
WebSocket), add a `BackendKind` case, and add one `case` in `AppContainer.init`. Domain/ViewModels stay unchanged.
Not yet abstracted: feed, media upload, push notifications `FeedViewModel`, `EditProfileView`.

## Migration status (honest)
Done: auth (incl. reauth + deletion + password reset UI), user/contact lookup, chat send/sync/outbox/older-history paging, feed (repository, own-feed listener, reactions), photo refresh, error type, logging, config, mocks, unit tests.
Still Firebase-coupled: `ChatRoomViewModel` (profile URL update,
Firebase Storage upload), `UserProfile` (`@DocumentID`), `CoreDataUtils` (`import FirebaseCore`, legacy `FirebaseMessage`).

## Security
`firebase/*.rules.proposed` are drafts: **not deployed, not tested in the emulator**. See the header comments for
known gaps (feed reactions, `users.email` readable by any signed-in user, unverified phone numbers).

## Feed (tranche 2)
Schema kept (`user_feed/{phone}/posts/{postId}`); posts now use a client-generated id for every copy so republishing is
idempotent, and writes are chunked at 400 per batch. The listener reads only the user's **own** feed (previously one
listener per contact, which also read other people's feeds). Reactions moved to `post_reactions/{postId}/users/{uid}`
with aggregation-query counts; the old per-copy `likes`/`dislikes` increments never worked (each copy had a different
document id) and are no longer updated. Existing reaction data is not migrated (there was none that worked).

## Account deletion
The client re-authenticates, then deletes the Firebase Auth user. **Server-side cleanup is not implemented**: deploy the
Firebase "Delete User Data" extension or an `auth.user().onDelete` function to remove `users/{uid}`, chats, feed copies
and reactions. Without it the App Store account-deletion requirement is only partly met.

## Deep links and push (tranche 3)
- `Domain/DeepLink` parses and strictly validates `mybuddy://chat|profile|post/{id}` and notification payloads
  (`deepLink` URL string, or `chatId`). Unknown hosts, extra path segments and non `[A-Za-z0-9_-]` ids are dropped.
- `Core/DeepLinkRouter` is the single entry (`.onOpenURL`, notification tap). A link arriving on cold launch waits in
  `pending`. `ContentView` switches tabs; `ChatListView` opens the conversation once it exists locally (gives up after 10 s).
  Profile and post links only switch to the Contacts / Feed tab: there are no per-user or per-post screens yet.
- `PushNotificationService` (Firebase impl: FCM token stored at `users/{uid}/devices/{installationId}`) supports many
  devices per user; the token is removed on logout and account deletion (bounded 3 s wait so offline logout never hangs).
- Foreground banners are suppressed for the conversation currently on screen.
- `firebase/functions/index.js` is a **draft, undeployed, untested** function that sends the push on message creation
  (no message text in the payload).

### Manual steps required for push (cannot be done from code)
1. Xcode: Signing & Capabilities → add **Push Notifications** (creates the entitlements file; needs a paid developer team).
2. Apple Developer: create an APNs auth key; upload it in Firebase console → Project settings → Cloud Messaging.
3. Deploy the function (`firebase deploy --only functions`) after testing it in the emulator.

## Media (tranche 4)
- `ImageProcessor` resizes (never upscales; chat 1600 px, avatar 512 px) and JPEG-encodes off the main thread; bubbles decode
  thumbnails via `ImageMemoryCache` (bounded NSCache) instead of the full bitmap on every render.
- `MediaRepository` (Firebase Storage impl) replaces the unsigned Cloudinary upload. Paths: `chat_images/{uid}/{messageId}.jpg`
  (idempotent per message) and `avatars/{uid}/{uuid}.jpg`. Old Cloudinary / `images/` URLs still display.
- Image send: stored locally immediately (`sent == false`, empty media url, bytes in `mediaData`), then `OutboxRetrier`
  uploads and sends. A failed upload or a lost response is retried on reconnect/foreground, so images are no longer silently
  lost. Downloaded images are stored downscaled; non-image media is not cached.
- Not done: upload progress UI (the repository exposes `onProgress`, nothing consumes it), video, background `URLSession`
  uploads, cancel-in-flight UI, a visible "failed" state (needs the Core Data v2 model).
- **Disable the unsigned Cloudinary upload preset `chat_uploads`** in the Cloudinary dashboard once all clients are updated.

## Local store v2 (tranche 5)
- Core Data model **`MyBuddy 2`** (current) adds `Message.deliveryState` (0 sending, 1 sent, 2 failed) and fetch indexes
  (`Message(chatId,timestamp)`, `Message(id)`, `Message(senderId,sent)`, `ChatMsg(id)`, `Contact(phoneNumber)`, `Feed(id)`).
  v1 stores migrate with **lightweight** migration (new attribute has a default; indexes are metadata only). No unique
  constraints were added: they can fail migration if duplicate rows already exist.
- `ChatMsg.messages` (to-one, unused, no inverse) was left untouched on purpose: nothing reads it.
- Outbox states: retryable errors keep `sending` and are retried on reconnect/foreground; a permanent rejection sets `failed`
  (persisted, survives relaunch) and shows a red retry button / context menu (Retry, Delete). Only unsent rows can be deleted.
- `PersistenceController` no longer crashes the app if the store cannot load: it rebuilds the store once (unsent messages in
  an unreadable store are lost, logged at `fault`), and only then gives up.
- Never edit model version 1 again; add `MyBuddy 3` for any further change.
