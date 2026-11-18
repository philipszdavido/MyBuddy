# MyBuddy backend

NestJS (TypeScript, strict) modular monolith: one codebase, two processes.

| Process | Entry | Role |
|---|---|---|
| API | `dist/main.js` | REST `/api/v1`, Socket.IO `/realtime`, Swagger at `/docs` (non-production) |
| Worker | `dist/worker.js` | BullMQ consumers + recurring schedules (no HTTP) |

PostgreSQL (Prisma) is the source of truth. Redis holds caches, rate limits, presence, the Socket.IO
adapter and BullMQ. Media lives in Cloudflare R2 (S3 API). Firebase Auth issues identities (ID tokens
verified with the Admin SDK) and FCM delivers push notifications.

Design and decisions: [`docs/REBUILD_AUDIT.md`](../docs/REBUILD_AUDIT.md). Real-time protocol:
[`docs/backend/REALTIME.md`](../docs/backend/REALTIME.md). Deployment, migrations and rollback:
[`docs/backend/DEPLOYMENT.md`](../docs/backend/DEPLOYMENT.md). API contract: `openapi.json`
(regenerate with `npm run openapi` while the stack is up).

## Quick start

```sh
cd backend
cp .env.example .env                       # fill in Firebase (or FIREBASE_AUTH_EMULATOR_HOST) and keep the local R2/S3 values
docker compose up -d postgres redis s3     # Postgres :5433, Redis :6380, S3 mock :9090 (buckets mybuddy-dev, mybuddy-test)
npm install
npx prisma migrate deploy && npx prisma generate
npm run dev                                # API on :3000, Swagger on /docs
npm run dev:worker                         # in another terminal
```

Full stack in containers: `docker compose --profile app up --build` (runs migrations first).

## Commands

| Task | Command |
|---|---|
| Typecheck / lint | `npm run typecheck` / `npm run lint` |
| Unit tests | `npm test` |
| Integration tests (needs the compose deps) | `npm run test:int` |
| One integration file / test | `npx jest --config test/jest-int.json --runInBand test/social -t "blocking"` |
| Production build | `npm run build` → `dist/` |
| Apply migrations | `npm run db:migrate` (`prisma migrate deploy`) |
| New migration | `npx prisma migrate dev --create-only --name <name>` — see "Migrations" |
| Export OpenAPI | `npm run openapi` (or `curl localhost:3000/docs-json > openapi.json`) |
| Docker image | `docker build -t mybuddy-backend .` |

Integration tests use a dedicated `mybuddy_test` database and Redis DB 1, run every BullMQ processor
in-process, and fake only Firebase token verification and FCM sending (`test/harness.ts`).
`test/ios-contract.int.ts` compiles the iOS app's `Data/API` layer with `swiftc` and runs it against the
server (skipped when no Swift toolchain is installed).

## Layout

```
src/
  main.ts / worker.ts / worker.module.ts    entrypoints (API / workers)
  app.module.ts / bootstrap.ts              module graph, global pipes/filters/helmet/CORS/versioning
  config/env.ts                             every env var, validated at boot
  auth/                                     Firebase token verifier, global guard, user provisioning
  common/                                   errors, cursor pagination, decorators, audit log, rate limiting
  users/ graph/ posts/ comments/ engagement/ feed/ media/ messaging/ realtime/
  notifications/ search/ analytics/ moderation/ accounts/ cleanup/ email/ queues/
prisma/schema.prisma + migrations/          schema; raw SQL for FTS, trigram, CHECKs, triggers
test/                                       integration suites + harness + iOS contract driver
```

Conventions that span modules:
- **Identity** comes only from the verified token (`@CurrentUser()`); ids in paths/bodies are data.
  `ValidationPipe` runs with `whitelist` + `forbidNonWhitelisted`, so protected fields are rejected.
- **Privacy** decisions go through `graph/relationship.service.ts` (`visiblePostSql`, `blockedEitherWaySql`).
  Never re-implement block/visibility rules in a module.
- **Counters** (likes, comments, followers, …) change in the same transaction as the rows they count;
  the nightly `counter-reconcile` job is a safety net, not the mechanism.
- **Side effects after commit**: notifications are written in the transaction (outbox) and dispatched
  after it; feed fan-out, media processing, analytics and email are BullMQ jobs. Nothing calls FCM, R2
  processing or email inside a transaction or on the request path.
- **Pagination** is keyset (`common/pagination/cursor.ts`), never OFFSET, except relevance-ranked
  search (bounded to 200 results).
- **Errors**: throw `AppError`; clients receive `{ "error": { "code", "message", "details?", "requestId" } }`.

## Migrations

Prisma cannot express full-text `tsvector` columns, trigram/BRIN/partial indexes, CHECK constraints or
triggers, so those are hand-written SQL in the migrations. Consequently `prisma migrate dev` always
proposes `DROP INDEX …`/`ALTER … search_vector` statements for them: create migrations with
`--create-only`, **delete those generated lines**, keep only your change, then `prisma migrate deploy`.
Check drift with:

```sh
npx prisma migrate diff --from-migrations prisma/migrations --to-schema-datamodel prisma/schema.prisma \
  --shadow-database-url postgresql://mybuddy:mybuddy@localhost:5433/mybuddy_shadow --script
```

(only the known hand-written items may appear). Never edit an applied migration; add a new one.

## Background jobs

| Queue | Jobs |
|---|---|
| `feed-fanout` | `fanout`, `retract`, `backfill-follow`, `unfollow` |
| `notifications` | `deliver` (realtime + FCM, per-device delivery rows, dead-token pruning) |
| `media-image` / `media-video` | sharp variants / FFmpeg poster + H.264 renditions |
| `account-deletion` | R2 objects → DB (counters repaired, cascade) → Firebase user |
| `analytics` | `event`, `impressions`, `aggregate` (day/month) |
| `search-index` | `trending-hashtags` (OpenSearch indexing would go here) |
| `cleanup` | `notification-sweep` (1 min), `media-sweep` (1 h), `counter-reconcile`, `feed-trim`, `follow-requests` (daily) |
| `email` | `account-deleted`, `report-received` (SMTP; skipped when `SMTP_URL` is unset) |

Retries use exponential backoff (5 attempts by default); failed jobs are kept 14 days. Monitor with
Bull Board at `/admin/queues` (`ENABLE_QUEUE_DASHBOARD=true` + `QUEUE_DASHBOARD_PASSWORD`).
