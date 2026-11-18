import { getQueueToken } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import sharp from 'sharp';
import { AnalyticsProcessor } from '../src/analytics/analytics.module';
import { CleanupProcessor } from '../src/cleanup/cleanup.processor';
import { Q } from '../src/queues/queues';
import { createHarness, Harness, TestUser } from './harness';

const api = '/api/v1';

describe('search, moderation, analytics, cleanup and account deletion (integration)', () => {
  let h: Harness;
  let ada: TestUser;
  let bola: TestUser;
  let chi: TestUser;
  let mod: TestUser;

  const post = async (u: TestUser, body: Record<string, unknown>) => (await h.http().post(`${api}/posts`).set(u.auth).send(body).expect(201)).body as { id: string };

  beforeAll(async () => {
    h = await createHarness();
    ada = await h.user('o-ada', { username: 'adaeze', phone: '2346000000001' });
    bola = await h.user('o-bola', { username: 'bolaji', phone: '2346000000002' });
    chi = await h.user('o-chi', { username: 'chinedu' });
    mod = await h.user('o-mod', { username: 'moderator' });
    await h.prisma.user.update({ where: { id: mod.id }, data: { role: 'MODERATOR' } });
    await h.redis.del(`auth:user:${mod.uid}`);
  });
  afterAll(() => h.close());

  describe('search', () => {
    it('finds people by username prefix, name and typo, excluding blocked and hidden accounts', async () => {
      await h.http().patch(`${api}/users/me`).set(ada.auth).send({ displayName: 'Adaeze Okafor' }).expect(200);
      const prefix = await h.http().get(`${api}/search/users?q=ada`).set(chi.auth).expect(200);
      expect(prefix.body.items[0]).toMatchObject({ id: ada.id, username: 'adaeze' });
      const byName = await h.http().get(`${api}/search/users?q=okafor`).set(chi.auth).expect(200);
      expect(byName.body.items.map((u: { id: string }) => u.id)).toContain(ada.id);
      const typo = await h.http().get(`${api}/search/users?q=adeaze`).set(chi.auth).expect(200);
      expect(typo.body.items.map((u: { id: string }) => u.id)).toContain(ada.id);

      await h.http().patch(`${api}/users/me/settings`).set(bola.auth).send({ discoverable: false }).expect(200);
      expect((await h.http().get(`${api}/search/users?q=bolaji`).set(chi.auth).expect(200)).body.items).toEqual([]);
      await h.http().post(`${api}/users/${chi.id}/block`).set(ada.auth).expect(204);
      expect((await h.http().get(`${api}/search/users?q=adaeze`).set(chi.auth).expect(200)).body.items).toEqual([]);
      await h.http().delete(`${api}/users/${chi.id}/block`).set(ada.auth).expect(204);

      const recent = await h.http().get(`${api}/search/recent`).set(chi.auth).expect(200);
      expect(recent.body.items.map((r: { query: string }) => r.query)).toEqual(expect.arrayContaining(['adaeze', 'okafor']));
    });

    it('searches visible posts by text and hashtag; suggests and ranks hashtags', async () => {
      const pub = await post(ada, { text: 'Jollof rice recipe #NaijaFood', audience: 'PUBLIC' });
      const hidden = await post(ada, { text: 'Secret jollof for contacts #NaijaFood' }); // CONTACTS
      const byText = await h.http().get(`${api}/search/posts?q=jollof`).set(chi.auth).expect(200);
      expect(byText.body.items.map((p: { id: string }) => p.id)).toEqual([pub.id]);
      const byTag = await h.http().get(`${api}/search/posts?q=%23naijafood`).set(chi.auth).expect(200);
      expect(byTag.body.items.map((p: { id: string }) => p.id)).toEqual([pub.id]);
      expect(byTag.body.items.map((p: { id: string }) => p.id)).not.toContain(hidden.id);

      const suggest = await h.http().get(`${api}/search/suggest?q=naija`).set(chi.auth).expect(200);
      expect(suggest.body.hashtags[0]).toMatchObject({ tag: 'naijafood', postCount: 2 });
      await h.app.get(getQueueToken(Q.search)).add('trending-hashtags', {});
      await h.drain(Q.search);
      const trending = await h.http().get(`${api}/search/hashtags/trending`).set(chi.auth).expect(200);
      expect(trending.body.items.map((t: { tag: string }) => t.tag)).toContain('naijafood');
    });
  });

  describe('moderation', () => {
    it('lets users report what they can see, and only moderators act', async () => {
      const p = await post(bola, { text: 'buy followers now!!!', audience: 'PUBLIC' });
      const r1 = await h.http().post(`${api}/reports`).set(chi.auth).send({ targetType: 'POST', targetId: p.id, reason: 'SPAM' }).expect(201);
      const r2 = await h.http().post(`${api}/reports`).set(chi.auth).send({ targetType: 'POST', targetId: p.id, reason: 'SPAM' }).expect(201);
      expect(r2.body.id).toBe(r1.body.id); // folded duplicate
      await h.http().post(`${api}/reports`).set(chi.auth).send({ targetType: 'USER', targetId: chi.id, reason: 'SPAM' }).expect(400);

      await h.http().get(`${api}/admin/reports`).set(chi.auth).expect(403);
      const queue = await h.http().get(`${api}/admin/reports`).set(mod.auth).expect(200);
      expect(queue.body.items.map((r: { id: string }) => r.id)).toContain(r1.body.id);
      await h.http().post(`${api}/admin/reports/${r1.body.id}/actions`).set(mod.auth).send({ type: 'REMOVE_POST', note: 'spam' }).expect(201);
      await h.http().get(`${api}/posts/${p.id}`).set(ada.auth).expect(404);
      expect(await h.prisma.auditLog.count({ where: { action: 'moderation.remove_post', actorId: mod.id } })).toBe(1);
    });

    it('suspension locks the account immediately', async () => {
      const r = await h.http().post(`${api}/reports`).set(ada.auth).send({ targetType: 'USER', targetId: bola.id, reason: 'HARASSMENT' }).expect(201);
      await h.http().post(`${api}/admin/reports/${r.body.id}/actions`).set(mod.auth).send({ type: 'SUSPEND_USER' }).expect(201);
      const blocked = await h.http().post(`${api}/posts`).set(bola.auth).send({ text: 'am I still here?' }).expect(403);
      expect(blocked.body.error.code).toBe('ACCOUNT_SUSPENDED');
      await h.http().get(`${api}/users/me`).set(bola.auth).expect(200); // may still see own status
      await h.http().get(`${api}/users/bolaji`).set(ada.auth).expect(404);
      expect(h.verifier.revoked.has(bola.uid)).toBe(true);
      await h.http().post(`${api}/admin/reports/${r.body.id}/actions`).set(mod.auth).send({ type: 'RESTORE_USER' }).expect(201);
      await h.http().get(`${api}/users/bolaji`).set(ada.auth).expect(200);
    });
  });

  describe('analytics', () => {
    it('de-duplicates impressions per viewer per day and aggregates platform metrics', async () => {
      const p = await post(ada, { text: 'count my views', audience: 'PUBLIC' });
      await h.http().post(`${api}/feed/impressions`).set(chi.auth).send({ postIds: [p.id, p.id] }).expect(202);
      await h.http().post(`${api}/feed/impressions`).set(chi.auth).send({ postIds: [p.id] }).expect(202);
      await h.http().post(`${api}/feed/impressions`).set(ada.auth).send({ postIds: [p.id] }).expect(202); // own views don't count
      await h.drain(Q.analytics);
      expect((await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } })).impressionCount).toBe(1);
      const insights = await h.http().get(`${api}/posts/${p.id}/insights`).set(ada.auth).expect(200);
      expect(insights.body).toMatchObject({ reach: 1, impressions: 2 });
      await h.http().get(`${api}/posts/${p.id}/insights`).set(chi.auth).expect(404);

      await h.app.get(AnalyticsProcessor).aggregate('day');
      const admin = await h.user('o-admin');
      await h.prisma.user.update({ where: { id: admin.id }, data: { role: 'ADMIN' } });
      await h.redis.del(`auth:user:${admin.uid}`);
      const metrics = await h.http().get(`${api}/admin/metrics?metric=posts.created`).set(admin.auth).expect(200);
      expect(metrics.body.points.at(-1).value).toBeGreaterThanOrEqual(3);
      const active = await h.http().get(`${api}/admin/metrics?metric=users.active`).set(admin.auth).expect(200);
      expect(active.body.points.at(-1).value).toBeGreaterThanOrEqual(1);
      await h.http().get(`${api}/admin/metrics?metric=posts.created`).set(mod.auth).expect(403);
    });
  });

  describe('cleanup', () => {
    it('reconciles drifted counters and sweeps abandoned uploads', async () => {
      const p = await post(ada, { text: 'drift', audience: 'PUBLIC' });
      await h.http().post(`${api}/posts/${p.id}/like`).set(chi.auth).expect(201);
      await h.prisma.$executeRaw`UPDATE posts SET like_count = 42 WHERE id = ${p.id}::uuid`;
      const fixed = await h.app.get(CleanupProcessor).reconcileCounters();
      expect(fixed.posts).toBeGreaterThanOrEqual(1);
      expect((await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } })).likeCount).toBe(1);

      const ticket = await h.http().post(`${api}/media/upload-url`).set(ada.auth).send({ purpose: 'POST', mimeType: 'image/jpeg', sizeBytes: 100 }).expect(201);
      await h.prisma.mediaAsset.update({ where: { id: ticket.body.mediaId }, data: { createdAt: new Date(Date.now() - 2 * 86400_000) } });
      await h.app.get(getQueueToken(Q.cleanup)).add('media-sweep', {});
      await h.app.get(CleanupProcessor).process({ name: 'media-sweep' } as never);
      expect(await h.prisma.mediaAsset.count({ where: { id: ticket.body.mediaId } })).toBe(0);
    });

    it('re-dispatches notifications whose delivery job was lost', async () => {
      const n = await h.prisma.notification.create({
        data: { recipientId: ada.id, actorId: chi.id, type: 'FOLLOW', dedupeKey: 'lost-1', createdAt: new Date(Date.now() - 5 * 60_000) },
      });
      await h.app.get(CleanupProcessor).process({ name: 'notification-sweep' } as never);
      await h.drain(Q.notifications);
      expect((await h.prisma.notification.findUniqueOrThrow({ where: { id: n.id } })).pushProcessedAt).not.toBeNull();
    });
  });

  describe('account deletion', () => {
    it('removes the user, their data and media, repairs counters elsewhere, keeps others’ conversations', async () => {
      const gone = await h.user('o-gone', { username: 'leaving', phone: '2346000000099' });
      const adaPost = await post(ada, { text: 'popular post', audience: 'PUBLIC' });
      await h.http().post(`${api}/users/${ada.id}/follow`).set(gone.auth).expect(201);
      await h.http().post(`${api}/posts/${adaPost.id}/like`).set(gone.auth).expect(201);
      await h.http().post(`${api}/posts/${adaPost.id}/comments`).set(gone.auth).send({ text: 'nice' }).expect(201);
      await h.http().post(`${api}/posts/${adaPost.id}/repost`).set(gone.auth).expect(201);
      await h.http().post(`${api}/posts/${adaPost.id}/save`).set(gone.auth).expect(201);
      const own = await post(gone, { text: 'my last post #farewell', audience: 'PUBLIC' });
      const conv = await h.http().post(`${api}/conversations`).set(ada.auth).send({ participantIds: [gone.id] }).expect(201);
      await h.http().post(`${api}/conversations/${conv.body.id}/messages`).set(ada.auth).send({ clientId: 'bye-1', text: 'bye?' }).expect(201);
      const jpeg = await sharp({ create: { width: 50, height: 50, channels: 3, background: '#0f0' } }).jpeg().toBuffer();
      const ticket = await h.http().post(`${api}/media/upload-url`).set(gone.auth).send({ purpose: 'AVATAR', mimeType: 'image/jpeg', sizeBytes: jpeg.length }).expect(201);
      await fetch(ticket.body.uploadUrl, { method: 'PUT', headers: { 'Content-Type': 'image/jpeg' }, body: jpeg });
      await h.http().post(`${api}/media/complete`).set(gone.auth).send({ mediaId: ticket.body.mediaId }).expect(201);
      await h.drain(Q.media, Q.feed);
      const avatar = await h.prisma.mediaAsset.findUniqueOrThrow({ where: { id: ticket.body.mediaId } });
      const thumbKey = (avatar.variants as { thumb: { key: string } }).thumb.key;

      const before = await h.prisma.post.findUniqueOrThrow({ where: { id: adaPost.id } });
      expect([before.likeCount, before.commentCount, before.repostCount, before.saveCount]).toEqual([1, 1, 1, 1]);

      await h.http().delete(`${api}/users/me`).set(gone.auth).expect(202);
      await h.drain(Q.accountDeletion);

      expect(await h.prisma.user.count({ where: { id: gone.id } })).toBe(0);
      expect(await h.prisma.post.count({ where: { id: own.id } })).toBe(0);
      expect(h.verifier.deleted).toContain(gone.uid);
      const after = await h.prisma.post.findUniqueOrThrow({ where: { id: adaPost.id } });
      expect([after.likeCount, after.commentCount, after.repostCount, after.saveCount]).toEqual([0, 0, 0, 0]);
      expect((await h.prisma.userProfile.findUniqueOrThrow({ where: { userId: ada.id } })).followersCount).toBe(0);
      expect((await h.prisma.hashtag.findUnique({ where: { tag: 'farewell' } }))?.postCount ?? 0).toBe(0);
      expect((await fetch(`${process.env.R2_PUBLIC_URL}/${thumbKey}`)).status).toBe(404);
      // ada keeps the conversation and her own messages
      const kept = await h.http().get(`${api}/conversations/${conv.body.id}/messages`).set(ada.auth).expect(200);
      expect(kept.body.items.map((m: { text: string }) => m.text)).toEqual(['bye?']);
      expect(await h.prisma.auditLog.count({ where: { action: 'account.deleted', actorId: gone.id } })).toBe(1);

      // re-running the job is harmless
      const queue = h.app.get<Queue>(getQueueToken(Q.accountDeletion));
      await queue.add('delete', { userId: gone.id, firebaseUid: gone.uid }, { jobId: `delete-again-${gone.id}` });
      await h.drain(Q.accountDeletion);
      const failed = await queue.getFailed();
      expect(failed).toHaveLength(0);
    });
  });
});
