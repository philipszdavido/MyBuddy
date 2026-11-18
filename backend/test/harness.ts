import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { getQueueToken } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type Redis from 'ioredis';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { ProcessorsModule } from '../src/worker.module';
import { FcmSender, PushMessage, PushResult } from '../src/notifications/fcm.sender';
import { RedisIoAdapter } from '../src/realtime/redis-io.adapter';
import { TokenVerifier, VerifiedToken } from '../src/auth/token-verifier';
import { configureApp } from '../src/bootstrap';
import { AppError } from '../src/common/errors/app-error';
import { PrismaService } from '../src/prisma/prisma.service';
import { Q } from '../src/queues/queues';
import { REDIS } from '../src/redis/redis.module';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = process.env.TEST_DATABASE_URL ?? 'postgresql://mybuddy:mybuddy@localhost:5433/mybuddy_test?schema=public';
process.env.REDIS_URL = process.env.TEST_REDIS_URL ?? 'redis://localhost:6380/1';
process.env.LOG_LEVEL = 'silent';
process.env.R2_ENDPOINT = process.env.TEST_R2_ENDPOINT ?? 'http://localhost:9090';
process.env.R2_BUCKET_NAME = 'mybuddy-test';
process.env.R2_ACCESS_KEY_ID = 'test';
process.env.R2_SECRET_ACCESS_KEY = 'test';
process.env.R2_PUBLIC_URL = `${process.env.R2_ENDPOINT}/mybuddy-test`;

/**
 * Test double for Firebase token verification only (everything else is real: Postgres, Redis, BullMQ).
 * A token is "test:<uid>[:<email>[:verified]]". Firebase verification itself is covered by
 * FirebaseTokenVerifier's own tests against the Auth emulator when FIREBASE_AUTH_EMULATOR_HOST is set.
 */
export class FakeTokenVerifier extends TokenVerifier {
  revoked = new Set<string>();
  deleted: string[] = [];

  async verify(idToken: string, checkRevoked: boolean): Promise<VerifiedToken> {
    const [scheme, uid, email, verified, phone] = idToken.split(':');
    if (scheme !== 'test' || !uid) throw AppError.unauthenticated('Invalid or expired token');
    if (checkRevoked && this.revoked.has(uid)) throw AppError.unauthenticated('Session has been revoked, sign in again', 'TOKEN_REVOKED');
    return { uid, email: email || `${uid}@example.com`, emailVerified: verified === 'v', phoneNumber: phone || undefined, expiresAt: new Date(Date.now() + 3600_000) };
  }

  async deleteUser(uid: string) {
    this.deleted.push(uid);
  }

  async revokeSessions(uid: string) {
    this.revoked.add(uid);
  }
}

/** Records pushes instead of calling FCM. Tokens starting with "dead" behave like unregistered tokens. */
export class FakeFcmSender extends FcmSender {
  sent: Array<{ token: string; message: PushMessage }> = [];

  async send(tokens: string[], message: PushMessage): Promise<PushResult[]> {
    return tokens.map((token) => {
      if (token.startsWith('dead')) return { token, ok: false, invalidToken: true, error: 'messaging/registration-token-not-registered' };
      this.sent.push({ token, message });
      return { token, ok: true, invalidToken: false };
    });
  }
}

export interface Harness {
  /** Base URL of the listening server (for Socket.IO clients). */
  url: string;
  fcm: FakeFcmSender;
  app: INestApplication;
  prisma: PrismaService;
  redis: Redis;
  verifier: FakeTokenVerifier;
  http: () => ReturnType<typeof request>;
  /** Waits until the given queues have no pending or running jobs (processors run in-process in tests). */
  drain: (...queues: string[]) => Promise<void>;
  /** Authenticated user: provisions it through GET /users/me and returns its id + auth header. */
  user: (uid: string, opts?: { username?: string; phone?: string; visibility?: 'PUBLIC' | 'PRIVATE' }) => Promise<TestUser>;
  close: () => Promise<void>;
}

export interface TestUser {
  id: string;
  uid: string;
  auth: { Authorization: string };
}

const TABLES_IN_DELETE_ORDER = [
  'notification_deliveries', 'notifications', 'notification_preferences', 'message_reactions', 'message_attachments',
  'messages', 'conversation_participants', 'conversations', 'feed_entries', 'post_impressions', 'post_shares', 'saved_posts',
  'mentions', 'post_hashtags', 'hashtags', 'comment_reactions', 'post_reactions', 'comments', 'post_media', 'posts',
  'moderation_actions', 'reports', 'audit_logs', 'recent_searches', 'activity_events', 'metric_aggregates', 'contact_links',
  'follow_requests', 'follows', 'user_blocks', 'user_mutes', 'user_devices', 'user_settings', 'user_profiles', 'media_assets', 'users',
];

export async function resetDatabase(prisma: PrismaService) {
  await prisma.$executeRawUnsafe(`TRUNCATE ${TABLES_IN_DELETE_ORDER.map((t) => `"${t}"`).join(', ')} RESTART IDENTITY CASCADE`);
}

export async function createHarness(): Promise<Harness> {
  // Wipe queues before any in-process worker starts (wiping under a running worker races its job locks).
  const { Queue: BullQueue } = await import('bullmq');
  const { createRedis } = await import('../src/redis/redis.module');
  const conn = createRedis(process.env.REDIS_URL!, true);
  for (const name of Object.values(Q)) {
    const q = new BullQueue(name, { connection: conn, prefix: 'mb' });
    await q.obliterate({ force: true }).catch(() => undefined);
    await q.close();
  }
  await conn.quit();

  const verifier = new FakeTokenVerifier();
  const fcm = new FakeFcmSender();
  const moduleRef = await Test.createTestingModule({ imports: [AppModule, ProcessorsModule] })
    .overrideProvider(TokenVerifier)
    .useValue(verifier)
    .overrideProvider(FcmSender)
    .useValue(fcm)
    .compile();
  const app = moduleRef.createNestApplication({ logger: false });
  configureApp(app);
  const io = new RedisIoAdapter(app, process.env.REDIS_URL!);
  io.connect();
  app.useWebSocketAdapter(io);
  await app.listen(0, '127.0.0.1');
  const address = app.getHttpServer().address() as { port: number };
  const url = `http://127.0.0.1:${address.port}`;

  const prisma = app.get(PrismaService);
  const redis = app.get<Redis>(REDIS);
  // Reset both stores together, after boot and before any request: the auth cache must never point
  // at rows from a previous suite.
  await resetDatabase(prisma);
  await redis.flushdb();

  const http = () => request(app.getHttpServer());
  const user = async (uid: string, opts: { username?: string; phone?: string; visibility?: 'PUBLIC' | 'PRIVATE' } = {}): Promise<TestUser> => {
    const auth = { Authorization: `Bearer test:${uid}:${uid}@example.com:v` };
    const me = await http().get('/api/v1/users/me').set(auth).expect(200);
    const patch: Record<string, string> = {};
    if (opts.username) patch.username = opts.username;
    if (opts.phone) patch.phoneNumber = opts.phone;
    if (opts.visibility) patch.visibility = opts.visibility;
    if (Object.keys(patch).length) await http().patch('/api/v1/users/me').set(auth).send(patch).expect(200);
    return { id: (me.body as { id: string }).id, uid, auth };
  };

  const drain = async (...names: string[]) => {
    const deadline = Date.now() + 15_000;
    for (const name of names.length ? names : [Q.feed]) {
      const queue = app.get<Queue>(getQueueToken(name));
      for (;;) {
        const c = await queue.getJobCounts('waiting', 'active', 'delayed', 'prioritized', 'waiting-children');
        if (Object.values(c).every((n) => n === 0)) break;
        if (Date.now() > deadline) throw new Error(`queue ${name} did not drain: ${JSON.stringify(c)}`);
        await new Promise((r) => setTimeout(r, 25));
      }
    }
  };

  return {
    url,
    fcm,
    app,
    drain,
    prisma,
    redis,
    verifier,
    http,
    user,
    close: async () => {
      await app.close();
    },
  };
}
