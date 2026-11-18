# MyBuddy backend rebuild — Milestone 1: audit, target architecture, migration plan

Status (2026-11-13): milestones 1–9 implemented and tested locally; see §7 for results and remaining
work. Spec: `rebuild_prompt.md`. Backend: [`backend/README.md`](../backend/README.md).

---

## 1. Existing architecture

### Frontend
- Native iOS, **SwiftUI**, iOS 17.2 deployment target, Swift 5 language mode, Core Data local cache (model `MyBuddy 2`).
- No web or Android client.
- Layering already supports a backend swap: views talk to view models, view models talk to protocols in
  `Domain/Repositories.swift`, and `Composition/AppContainer` chooses the implementation (`Data/Firebase` or
  `Data/Mock`). `AppConfiguration.BackendKind` already has a commented-out `restAPI` case. Adding a REST/WebSocket
  backend means adding a `Data/API/` folder of implementations; the views don't change.
- Still coupled to Firebase outside `Data/`: `ChatRoomViewModel`, `UserProfile` (`@DocumentID`), `CoreDataUtils`,
  `FirebaseChatMsg` / `FirebaseMessage`, and `MyBuddyApp` (FCM delegate, which stays).
- Status of the refactor: written but never compiled or run (see `docs/ios/HANDOFF.md`). A baseline build result is
  recorded in §8.

### Backend
- **There is no server.** Clients write directly to Firestore and Storage. `firebase/functions/index.js` (push on new
  message) is a draft that has never been deployed. Security rules are drafts (`*.rules.proposed`) and have not
  been deployed. Nothing on the server fans out feeds, deletes account data or moderates reports.

### Firestore data model (as written by the current client)
| Path | Fields | Notes |
|---|---|---|
| `users/{uid}` | email, displayName, phoneNumber (Int64), url, createdAt | readable by every signed-in user (leaks email) |
| `users/{uid}/devices/{installationId}` | token, platform, appVersion, updatedAt | FCM tokens, many per user |
| `users/{uid}/blocks/{blockedUid}` | phoneNumber, displayName, createdAt | |
| `reports/{auto}` | reporterId, targetUserId, reason, conversationId?, messageId?, status, createdAt | write-only for clients |
| `chats/{chatId}` | participants[2], lastMessage, lastSenderId, lastTimestamp, updatedAt, *PhoneNumber, type | `chatId` = the two **phone numbers**, sorted and joined |
| `chats/{chatId}/messages/{id}` | senderId, recipientId, content, timestamp, type (text/image), mediaUrl, seen, sent, *PhoneNumber | message id is generated on the client, so sends are idempotent |
| `user_feed/{phone}/posts/{postId}` | content, feedOwnerId (author phone as a string), timestamp, likes, dislikes | one copy per recipient, the same postId in every copy |
| `post_reactions/{postId}/users/{uid}` | type like/dislike, createdAt | |

Storage: `chat_images/{uid}/{messageId}.jpg`, `avatars/{uid}/{uuid}.jpg`, legacy `images/…`, and legacy **Cloudinary**
URLs embedded in older messages and profiles.

### Existing product features
| Feature | State |
|---|---|
| Email/password sign-up, sign-in, reset, verification, reauth, account deletion (Auth user only) | exists |
| Google / Apple sign-in | **not present** |
| Phone-contact matching (device address book → `users.phoneNumber`) | core of the product |
| 1:1 chat: text and images, outbox, retries, paging, failed state, "seen" flag | exists |
| Feed: **text-only** posts sent to all of the author's contacts; like/dislike | exists |
| Comments | flag `feedComments = false`, no implementation |
| Block / unblock, report user/message | exists |
| Push on new message (FCM), deep links `mybuddy://chat|profile|post/{id}` | client done, function not deployed |
| Profile: display name, phone, photo | exists, no username/bio/cover |
| AI Buddy | compiled out (`AI_BUDDY`), calls OpenAI from the client — must not ship as is |
| Follows, usernames, public profiles, discovery, groups, video, stories, search, in-app notifications, typing, presence | **not present** |

### Broken, incomplete or risky
1. **Identity rests on unverified phone numbers.** Anyone can claim any number. Chat IDs and feed paths are built from phone numbers.
2. Feed fan-out runs on the client, so a client can write into any phone's feed (acknowledged in the rules header).
3. Account deletion leaves all Firestore and Storage data behind (fails the App Store requirement).
4. `users.email` can be read by any signed-in user.
5. A Cloudinary API secret is in git history.
6. The refactor has never been compiled or tested.

---

## 2. Target architecture

```
iOS app (SwiftUI, unchanged UI)
  ├─ Firebase Auth SDK ──(ID token)──┐
  ├─ FCM SDK (receives pushes)       │
  ├─ Data/API: REST client  ─────────┼──▶  NestJS API (modular monolith, /api/v1, Swagger)
  └─ Data/API: Socket.IO client ─────┘         │  FirebaseAuthGuard (Admin SDK verifyIdToken)
                                               │  modules: users, social-graph, posts, comments,
                                               │  engagement, feed, messaging (WS gateway),
                                               │  notifications, media, search, moderation, analytics
                                               ├──▶ PostgreSQL (Prisma)  — source of truth
                                               ├──▶ Redis — cache, rate limits, presence, Socket.IO adapter, BullMQ
                                               └──▶ Cloudflare R2 (presigned PUT/GET, S3 API)
NestJS worker process (same codebase, different entrypoint)
  BullMQ queues: feed-fanout, notifications(FCM), email, media-image, media-video(FFmpeg),
                 search-index, analytics, cleanup, account-deletion
```

- **Repository layout:** a new `backend/` directory (NestJS + TypeScript strict + Prisma) next to the iOS app.
  `api` and `worker` are two entrypoints of one app, built into one Docker image.
- **Auth:** the client keeps Firebase Auth. Every REST and WebSocket request carries an ID token, which the backend
  verifies with the Admin SDK (checking revocation on sensitive routes). The first verified request upserts
  `users(firebase_uid)`. Roles (`user`, `moderator`, `admin`) live in Postgres, not in custom claims. User IDs
  supplied by the client are never trusted.
- **ORM:** the repo has no ORM, so this uses **Prisma** (schema and migrations). Raw SQL goes through `$queryRaw`
  with tagged templates for full-text search and feed ranking.
- **Real time:** a NestJS Socket.IO gateway with the Redis adapter. Rooms are `user:{id}` and `conversation:{id}`,
  and membership is checked against Postgres before joining. Every send has a client message ID and is persisted
  first, then emitted, and acknowledged with the server ID and sequence. A client that reconnects asks for
  `messages?after=<seq>`, so nothing is lost while disconnected. Presence and typing state live in Redis with TTLs.
- **Feed:** each user has a `feed_entries` table, filled by a BullMQ fan-out-on-write job for normal authors.
  Authors above a follower threshold are pulled at read time and merged in. Ranking is a separate `FeedRanker`
  interface (recency decay, relationship strength, engagement, diversity) that runs over a candidate set. Pages use
  an opaque cursor, the first page is cached in Redis, and blocks and mutes are filtered in SQL.
- **Media:** `POST /media/upload-url` validates type and size and returns a presigned PUT for a key of the form
  `u/{userId}/{uuid}`. `POST /media/complete` checks the object with HEAD and its magic bytes, then queues a
  sharp (image variants) or FFmpeg (video: HLS/MP4 renditions and a poster frame) job. Processing status is stored
  on `media_assets`. A cleanup job deletes uploads that are never completed.
- **Push:** notification rows are written in the domain transaction (outbox pattern) and a BullMQ job sends them
  through FCM, removes dead tokens and respects preferences. FCM is never called inside a transaction.

### Database (Prisma, UUID PKs, `created_at`/`updated_at`, soft delete on content)
Users: `users`, `user_profiles`, `user_settings`, `user_roles`, `user_devices` (FCM tokens), `user_blocks`,
`user_mutes`, `contact_links` (see decision A). Graph: `follows`, `follow_requests`. Content: `posts`, `post_media`,
`media_assets`, `comments` (self-referential `parent_id`), `reactions` (polymorphic target, unique per
user+target), `hashtags`, `post_hashtags`, `mentions`, `saved_posts`, `reposts`, `feed_entries`. Messaging:
`conversations`, `conversation_participants` (last_read_seq), `messages` (per-conversation `seq`, unique
`(conversation_id, client_id)`), `message_attachments`, `message_reactions`, `message_receipts`. Notifications:
`notifications`, `notification_preferences`, `notification_deliveries`. Moderation: `reports`,
`moderation_actions`, `audit_log`. Analytics: `activity_events` (partitioned by month), `daily_aggregates`.
Every table carries `legacy_id` columns where Firestore IDs need to map across, which makes the migration
idempotent.

---

## 3. Migration strategy (Firestore/Storage → Postgres/R2)

| Firestore source | Target | Mapping / risk |
|---|---|---|
| Auth users + `users/{uid}` | `users`, `user_profiles` | `firebase_uid` unique. **Duplicate phone numbers are possible** (unverified), so they are migrated as non-unique and the duplicates reported. |
| `devices` | `user_devices` | direct copy |
| `blocks` | `user_blocks` | direct copy |
| `reports` | `reports` | direct copy |
| `chats` + `messages` | `conversations` (`legacy_id` = phone-based chatId), `messages` (`client_id` = Firestore id) | `seq` assigned in timestamp order; `seen` becomes participant `last_read_seq` |
| `user_feed/*/posts/*` | `posts` (deduplicated on postId; author found by phone, which is **ambiguous if phones collide**) + `feed_entries` (one per copy) | |
| `post_reactions` | `reactions` | like/dislike kept |
| Storage + Cloudinary URLs | R2 (copied by a worker job) + `media_assets.legacy_url` | old URLs keep resolving through the stored legacy URL until the copy is verified; nothing is deleted from Firebase/Cloudinary |

- The scripts (`backend/scripts/migrate/*`) run per collection, in batches, with checkpoints, upserts keyed on
  `legacy_id`, a dry-run mode and a validation report (counts plus sampled diffs). They can be re-run safely.
- **The cutover is the main risk.** App Store builds already in use talk to Firestore directly and have no
  minimum-version check. If an old client and a new client chat, they will not see each other's messages.
  Plan:
  1. Ship a client update that adds a remote minimum-version gate, while still on Firebase.
  2. During the transition, run a **one-way Firestore → Postgres replicator** (a compatibility adapter, not a
     dual write). New clients write only to the API.
  3. Force-upgrade, stop the replicator, and lock Firestore with `allow write: if false`.
  4. Rollback: until step 3, Firestore stays complete for old clients, and the new clients' `BackendKind` can be
     switched back with a remote flag.
- Firestore/Storage are retired only after validation reports match and the R2 copy is verified.

---

## 4. Milestones (each ends with tests, lint and build passing)
1. Audit and plan (this document).
2. Backend foundation: NestJS, Prisma schema and migrations, Firebase guard and user provisioning, roles,
   config/env, Docker Compose (Postgres, Redis, api, worker), health checks, Swagger, error format, rate limits.
3. Social: profiles, graph (decision A), posts, comments, reactions, saved posts, reposts, feed and ranker.
4. Media: R2 presign/complete, image variants, video pipeline, orphan cleanup.
5. Real time: Socket.IO gateway, messaging, receipts, typing, presence, in-app notifications and FCM.
6. Jobs: consolidate the BullMQ queues, retries/backoff, monitoring (Bull Board, admin-only).
7. Search (Postgres FTS behind a `SearchProvider` interface) and analytics aggregation.
8. iOS: `Data/API/*` implementations of the existing protocols plus new protocols for the new features.
   **Existing screens unchanged**; new screens only for features the decisions approve.
9. Production readiness: migration scripts, replicator, security tests, load test, runbooks and rollback.

## 5. Decisions (2026-11-12)
- **A. Social graph: contacts and follows.** Contact matching stays the primary graph (`contact_links`, refreshed
  from the device address book). Usernames, public/private accounts, follows, follow requests and discovery are
  added on top. The audience for a post is `contacts`, `followers` or `public`; the existing behaviour maps to
  `contacts`.
- **B. Production data: none. Clean start.** Firestore and Storage are the development backend only. There is no
  replicator, no dual-version cutover and no data-migration scripts. The new iOS build switches to the API as a
  whole. Legacy media URLs in local caches still display, and nothing is deleted from Firebase or Cloudinary.
  §3 stays as reference in case real data appears before launch.
- **C. New iOS UI:** comments, image/video posts, notification inbox, search and profiles. Existing screens keep
  their layout.
- **D. AI Buddy:** stays compiled out.

## 6. Baseline iOS build
2026-11-12, Xcode-beta, `-destination 'generic/platform=iOS Simulator'`: **BUILD SUCCEEDED** (first build of the
refactor). The installed simulators run iOS 17.5, but the app target requires 17.6, so tests can't run on them
until a newer runtime is installed or the target is lowered.

## 7. Implementation status (2026-11-13)

| Milestone | Delivered | Verified by |
|---|---|---|
| 1 Audit | this document | – |
| 2 Foundation | NestJS API + worker, Prisma schema (42 tables) and 5 migrations, Firebase guard + provisioning, roles, env validation, error envelope, Redis rate limits, health, Swagger, Docker | integration tests, built image smoke-run |
| 3 Social | profiles, usernames, privacy, follows/requests, blocks/mutes, contact sync, suggestions, posts (text/media/quote/repost/drafts/pin/save/share), hashtags, mentions, comments + replies, reactions, hybrid fan-out feed, ranker, discover | `test/social.int.ts`, `ranker.spec.ts`, `text-entities.spec.ts` |
| 4 Media | presigned R2 upload, size + magic-byte verification, sharp variants (EXIF stripped), FFmpeg poster + H.264 720p/480p, orphan cleanup | `test/media.int.ts` (real JPEG/PNG/MOV), `sniff.spec.ts` |
| 5 Real time | Socket.IO gateway (token auth, membership checks, rate limit, Redis fan-out), messaging (seq, idempotent sends, receipts, typing, presence, edit/delete/reactions, requests, groups), FCM delivery, activity inbox, device tokens | `test/messaging.int.ts` (real socket clients) |
| 6 Jobs | 9 BullMQ queues, retries/backoff, schedules, account deletion, email, counter reconciliation, Bull Board | `test/operations.int.ts` |
| 7 Search & analytics | Postgres FTS + trigram behind `SearchProvider`, trending hashtags, recent searches; events, impressions, daily/monthly aggregates, post insights, admin metrics | `test/operations.int.ts` |
| 8 iOS | `Data/API` (REST client, Socket.IO client, repositories), `.api` backend in `AppContainer`, account-id fix, conversation-id resolution, new screens: social feed with media, composer (photos/videos, audience), comments, profiles + follow, search, activity inbox | `xcodebuild` (0 errors), 48 iOS unit tests, `test/ios-contract.int.ts` (the Swift API layer against the live backend, 20 checks) |
| 9 Readiness | `.env.example`, Dockerfile, compose, `docs/backend/DEPLOYMENT.md`, `docs/backend/REALTIME.md`, `openapi.json` | image built and run; API/worker graceful shutdown checked |

### Remaining work (not done)
- **Not exercised against real Firebase**: `FirebaseTokenVerifier` and `FirebaseFcmSender` are covered
  only by typechecking; tests replace them with fakes (no Firebase CLI or emulator here). Run one manual
  sign-in and push on staging.
- **iOS (2026-11-13 revamp)**: shared design system (`ios/MyBuddy/views/design/DesignSystem.swift`), restyled auth, feed,
  contacts and settings, plus new screens on the API backend: inbox with message requests, direct and group
  conversations (`ios/MyBuddy/views/messaging/`), group info (rename, add/remove members, mute, leave), profile editing
  with username check, privacy and notification settings (`ios/MyBuddy/views/account/`), and upload progress for posts,
  chat photos and avatars. Still missing: message edit/reactions UI, video in chat, drafts and pinned-post UI.
  The legacy Core Data chat (Firebase backend) only received light styling.
- Unsent text messages on the API backend are persisted (`PendingMessageStore`); unsent *photos* are kept only
  in memory and are lost if the app is killed before upload.
- **Security, before launch**: phone-number verification (see DEPLOYMENT.md checklist), Cloudinary secret
  rotation, App Check, penetration test.
- No load or performance testing yet. The feed and fan-out SQL is indexed but has not been benchmarked
  at scale.
- Email needs an SMTP provider (`SMTP_URL`). OpenSearch is intentionally not introduced.
- Legacy Firebase data code stays until the API build is fully adopted (spec §21).
