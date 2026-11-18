# Deployment, migration and rollback

## Topology
```
            ┌──────── load balancer (TLS, WebSocket upgrade) ────────┐
iOS app ──▶ │ api × N  (node dist/main.js, stateless)                 │──▶ PostgreSQL 16 (primary + replica for backups)
            └─────────────────────────────────────────────────────────┘──▶ Redis 7 (noeviction, AOF on)
              worker × M (node dist/worker.js)  ◀── BullMQ ──▶ Redis      ──▶ Cloudflare R2 bucket + public custom domain
              Firebase Auth (tokens) · FCM (push) · SMTP (optional)
```
- One Docker image (`backend/Dockerfile`) for both processes; only the command differs.
- API instances are stateless and scale horizontally (Socket.IO across instances via Redis).
- Workers scale independently. Video transcoding runs one job per worker process, so add worker
  replicas for video throughput. Give workers a stop grace period longer than the slowest job (120 s+):
  SIGTERM waits for in-flight jobs.
- Health: `GET /health/live` (process up; use for restarts) and `GET /health/ready` (Postgres and Redis
  reachable; use for load-balancer routing).

## Environments
`development`, `staging`, `production`. Each gets its own Firebase project, Postgres database, Redis
and R2 bucket. In `staging`/`production` the process refuses to start without Firebase and R2
credentials, and rejects `FIREBASE_AUTH_EMULATOR_HOST`. All variables: `backend/.env.example`. Inject
secrets from the platform's secret manager; never bake them into images.

## One-time setup
1. **Firebase**: create a service account with the *Firebase Authentication Admin* and *Firebase Cloud
   Messaging Admin* roles → `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`.
   Upload the APNs auth key in Firebase → Cloud Messaging (needed for iOS push).
2. **R2**: create a bucket and an API token scoped to *Object Read & Write* on that bucket only. Bind a
   custom domain (e.g. `media.mybuddy.app`) as `R2_PUBLIC_URL`. Allow public reads only under the
   `u/` prefix (originals are deleted after processing, so only processed variants are ever public).
   Non-public content (messages, contacts/followers posts) is served through short-lived signed URLs.
   Add a CORS rule only if a web client will upload (the iOS app does not need it).
3. **Postgres**: 16+, `pg_trgm` extension available (the first migration creates it).
4. **Redis**: `maxmemory-policy noeviction` (BullMQ requirement), persistence on.

## Release procedure
1. CI: `npm ci && npm run lint && npm run typecheck && npm test && npm run test:int && npm run build`.
2. Build and push the image.
3. **Migrate first**: run the image once with `npx prisma migrate deploy` (see compose `migrate`). Every
   migration in this repo is additive or backwards-compatible with the previous release, so old API
   pods keep working while new ones roll out. Keep it that way: rename/drop columns with
   expand → migrate data → contract over two releases.
4. Roll out API pods, then worker pods.
5. Smoke test: `/health/ready`, `GET /api/v1/users/me` with a test account, post + feed, a message
   between two test accounts, and an image upload.

## Rollback
- **Application**: redeploy the previous image tag (API and workers). Because migrations are
  backwards-compatible, the previous release runs against the new schema.
- **Database**: do not roll back schema in place. If a migration itself is faulty, ship a forward fix.
  For data damage, restore from point-in-time recovery into a new instance and repoint `DATABASE_URL`.
  Enable PITR/daily snapshots before launch.
- **Queues**: jobs are idempotent and keep their ids; a rollback simply resumes processing. Failed jobs
  can be retried from Bull Board.
- **iOS**: the backend is chosen by the `MBAPIBaseURL` Info.plist value. A build without it uses the
  previous Firebase backend, so the fallback is shipping (or keeping in review) a build without the key.

## Cutover from Firebase (clean start: decision B in docs/REBUILD_AUDIT.md)
There is no production Firestore data, so nothing is migrated or dual-written.
1. Deploy the backend to production and run the smoke test.
2. Set `MB_API_BASE_URL` (Release build setting) to the production API URL and ship the iOS build.
3. Keep the Firestore/Storage rules locked down (`allow read, write: if false`) for builds still using
   the old backend; delete the Firebase Storage/Firestore resources and the Cloudinary preset
   `chat_uploads` only after the API build is fully adopted (the spec forbids deleting them earlier).
If real data appears before launch, follow §3 of `docs/REBUILD_AUDIT.md` (batched, idempotent copy
keyed on legacy ids, plus a one-way Firestore→Postgres replicator during transition).

## Monitoring
- Logs: JSON (pino) to stdout, one line per request with `requestId` (also returned in error bodies).
  Authorization headers and request bodies are redacted.
- Queues: Bull Board (`/admin/queues`, basic auth). Alert on failed-job counts and on
  `notification-sweep` re-dispatching more than a handful of notifications (a sign that the outbox
  dispatch path is failing).
- Metrics: `GET /api/v1/admin/metrics?metric=…` (admin role) serves pre-aggregated daily/monthly product
  metrics: users.registered, users.active, posts.created, comments.created, reactions.created,
  follows.created, messages.sent, shares, impressions, video.views, engagement.rate.
- Audit trail: the `audit_logs` table records account deletion, blocks, moderation actions and staff
  removals.

## Security checklist (before launch)
- [ ] Rotate the Cloudinary secret that is in git history; disable preset `chat_uploads`.
- [ ] Restrict the Firebase iOS API key to the bundle id; enable App Check.
- [ ] Decide on phone verification: numbers are self-declared unless the user signs in with Firebase
      phone auth (then the verified number from the token wins). Contact matching trusts declared
      numbers, so someone could claim another person's number and see that person's CONTACTS posts.
      Turning on Firebase phone verification closes this.
- [ ] Grant the first ADMIN/MODERATOR roles directly in SQL (`UPDATE users SET role = 'ADMIN' …`); there
      is deliberately no API to self-promote.
- [ ] `CORS_ORIGINS` empty unless a browser client exists; Bull Board only on the internal network.
- [ ] Malware scanning: images are re-encoded (sharp) and videos re-transcoded (FFmpeg) before being
      served, and originals are deleted, which neutralises most payloads. If you need AV scanning of
      originals for compliance, add it as a step in the media processors before processing.
