import { InjectQueue } from '@nestjs/bullmq';
import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import type Redis from 'ioredis';
import { REDIS } from '../redis/redis.module';
import { followingCacheKey } from '../feed/feed.service';
import { Prisma, UserRole } from '@prisma/client';
import { Queue } from 'bullmq';
import { AuditService } from '../common/audit.service';
import { AuthContext } from '../common/decorators/auth.decorators';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, Page, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { extractEntities } from '../content/text-entities';
import { RelationshipService } from '../graph/relationship.service';
import { NewNotification, NotificationWriter } from '../notifications/notification-writer.service';
import { isUniqueViolation, PrismaService, Tx } from '../prisma/prisma.service';
import { AnalyticsEventJob, FanoutPostJob, Q, RetractPostJob } from '../queues/queues';
import { PostPresenter, PostView } from './post-presenter.service';
import { CreatePostDto, UpdatePostDto } from './posts.dto';

const STAFF: UserRole[] = ['MODERATOR', 'ADMIN'];

@Injectable()
export class PostsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly presenter: PostPresenter,
    private readonly relationships: RelationshipService,
    private readonly notifications: NotificationWriter,
    private readonly audit: AuditService,
    @InjectQueue(Q.feed) private readonly feedQueue: Queue<FanoutPostJob | RetractPostJob>,
    @InjectQueue(Q.analytics) private readonly analytics: Queue<AnalyticsEventJob>,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  // ─── Create / edit / delete ────────────────────────────────────────────────

  async create(authorId: string, dto: CreatePostDto): Promise<PostView> {
    const text = dto.text?.trim() || null;
    const mediaIds = dto.mediaIds ?? [];
    if (!text && mediaIds.length === 0) throw AppError.badRequest('A post needs text or media');
    if (new Set(mediaIds).size !== mediaIds.length) throw AppError.badRequest('Duplicate media id');

    if (dto.clientId) {
      const existing = await this.prisma.post.findUnique({ where: { authorId_clientId: { authorId, clientId: dto.clientId } }, select: { id: true } });
      if (existing) return this.view(authorId, existing.id);
    }

    const published = !dto.draft;
    if (published && text) {
      // Spam guard: the same text from the same author within 5 minutes is a duplicate, not a new post.
      const duplicate = await this.prisma.post.count({
        where: { authorId, text, deletedAt: null, status: 'PUBLISHED', createdAt: { gt: new Date(Date.now() - 5 * 60_000) } },
      });
      if (duplicate) throw AppError.conflict('You just posted this');
    }
    let result: { id: string; notify: string[] };
    try {
      result = await this.prisma.$transaction(async (tx) => {
        if (dto.quoteOfId) await this.assertRepostable(tx, authorId, dto.quoteOfId);
        const post = await tx.post.create({
          data: {
            authorId,
            clientId: dto.clientId,
            text,
            audience: dto.audience ?? 'CONTACTS',
            status: published ? 'PUBLISHED' : 'DRAFT',
            publishedAt: published ? new Date() : null,
            repostOfId: dto.quoteOfId,
          },
          select: { id: true },
        });
        await this.attachMedia(tx, authorId, post.id, mediaIds);
        const notify: NewNotification[] = [];
        if (published) {
          notify.push(...(await this.onPublished(tx, authorId, post.id, text)));
          if (dto.quoteOfId) notify.push(...(await this.onReposted(tx, authorId, post.id, dto.quoteOfId)));
        }
        return { id: post.id, notify: await this.notifications.write(tx, notify) };
      });
    } catch (error) {
      // Concurrent retry with the same clientId: return the post the other request created.
      if (dto.clientId && isUniqueViolation(error, 'client_id')) {
        const existing = await this.prisma.post.findUniqueOrThrow({ where: { authorId_clientId: { authorId, clientId: dto.clientId } }, select: { id: true } });
        return this.view(authorId, existing.id);
      }
      if (dto.quoteOfId && isUniqueViolation(error, 'repost_of_id')) throw AppError.conflict('You already reposted this post');
      throw error;
    }
    await this.notifications.dispatch(result.notify);
    if (published) await this.afterPublish(authorId, result.id);
    return this.view(authorId, result.id);
  }

  async update(authorId: string, postId: string, dto: UpdatePostDto): Promise<PostView> {
    const { notify, audienceChanged, published } = await this.prisma.$transaction(async (tx) => {
      const post = await this.ownPost(tx, authorId, postId);
      const text = dto.text === undefined ? post.text : dto.text?.trim() || null;
      const hasMedia = (await tx.postMedia.count({ where: { postId } })) > 0;
      if (!text && !hasMedia && !post.repostOfId) throw AppError.badRequest('A post needs text or media');
      const audienceChanged = dto.audience !== undefined && dto.audience !== post.audience;
      if (audienceChanged && post.repostOfId) throw AppError.badRequest('The audience of a repost cannot be changed');
      await tx.post.update({
        where: { id: postId },
        data: { text, audience: dto.audience, editedAt: post.status === 'PUBLISHED' ? new Date() : undefined },
      });
      let notify: NewNotification[] = [];
      if (post.status === 'PUBLISHED') {
        notify = await this.syncEntities(tx, authorId, postId, post.text, text);
      }
      return { notify: await this.notifications.write(tx, notify), audienceChanged, published: post.status === 'PUBLISHED' };
    });
    await this.notifications.dispatch(notify);
    if (published && audienceChanged) {
      // Narrowed audience: prune feeds. Widened: fan out to the new audience (idempotent inserts).
      await this.feedQueue.add('retract', { postId }, { jobId: `rt-${postId}-${Date.now()}` });
      await this.feedQueue.add('fanout', { postId }, { jobId: `fo-${postId}-${Date.now()}` });
    }
    return this.view(authorId, postId);
  }

  async publishDraft(authorId: string, postId: string): Promise<PostView> {
    const notify = await this.prisma.$transaction(async (tx) => {
      const post = await this.ownPost(tx, authorId, postId);
      if (post.status !== 'DRAFT') throw AppError.conflict('Post is already published');
      await tx.post.update({ where: { id: postId }, data: { status: 'PUBLISHED', publishedAt: new Date() } });
      const items = await this.onPublished(tx, authorId, postId, post.text);
      if (post.repostOfId) items.push(...(await this.onReposted(tx, authorId, postId, post.repostOfId)));
      return this.notifications.write(tx, items);
    });
    await this.notifications.dispatch(notify);
    await this.afterPublish(authorId, postId);
    return this.view(authorId, postId);
  }

  async remove(actor: AuthContext, postId: string): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      const post = await tx.post.findFirst({ where: { id: postId, deletedAt: null } });
      if (!post) throw AppError.notFound('Post');
      const isStaff = STAFF.includes(actor.role);
      if (post.authorId !== actor.userId && !isStaff) throw AppError.notFound('Post');
      await this.softDelete(tx, post);
      if (post.authorId !== actor.userId) {
        await this.audit.record({ actorId: actor.userId, action: 'post.remove', targetType: 'post', targetId: postId }, tx);
      }
    });
    await this.feedQueue.add('retract', { postId }, { jobId: `rt-${postId}-${Date.now()}` });
  }

  /** Shared with moderation and account deletion. Keeps every counter consistent. */
  async softDelete(tx: Tx, post: { id: string; authorId: string; status: string; repostOfId: string | null; text: string | null }): Promise<void> {
    await tx.post.update({ where: { id: post.id }, data: { deletedAt: new Date(), isPinned: false, repostOfId: null } });
    await tx.mediaAsset.updateMany({ where: { postMedia: { postId: post.id } }, data: { deletedAt: new Date() } });
    if (post.status !== 'PUBLISHED') return;
    await tx.$executeRaw`UPDATE user_profiles SET posts_count = GREATEST(posts_count - 1, 0) WHERE user_id = ${post.authorId}::uuid`;
    await this.syncHashtags(tx, post.id, extractEntities(post.text).hashtags, []);
    if (post.repostOfId) {
      await tx.$executeRaw`UPDATE posts SET repost_count = GREATEST(repost_count - 1, 0) WHERE id = ${post.repostOfId}::uuid`;
    }
  }

  // ─── Read ──────────────────────────────────────────────────────────────────

  async get(viewerId: string, postId: string): Promise<PostView> {
    if (!(await this.relationships.canViewPost(viewerId, postId))) throw AppError.notFound('Post');
    return this.view(viewerId, postId);
  }

  /** Profile "posts" tab. Pinned post first on the first page. Visibility is per post. */
  async byAuthor(viewerId: string, authorId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<PostView> & { pinned: PostView | null }> {
    if (await this.relationships.isBlockedEitherWay(viewerId, authorId)) throw AppError.notFound('User');
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.$queryRaw<Array<{ id: string; published_at: Date }>>`
      SELECT p.id, p.published_at FROM posts p
      WHERE p.author_id = ${authorId}::uuid AND NOT p.is_pinned
        AND ${this.relationships.visiblePostSql(viewerId)}
        ${c ? Prisma.sql`AND (p.published_at, p.id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
      ORDER BY p.published_at DESC, p.id DESC LIMIT ${limit + 1}`;
    let pinned: PostView | null = null;
    if (!cursor) {
      const pin = await this.prisma.$queryRaw<Array<{ id: string }>>`
        SELECT p.id FROM posts p WHERE p.author_id = ${authorId}::uuid AND p.is_pinned AND ${this.relationships.visiblePostSql(viewerId)} LIMIT 1`;
      pinned = pin[0] ? await this.presenter.presentOne(viewerId, pin[0].id) : null;
    }
    const page = toPage(rows, limit, (r) => r.id, (r) => timeCursor(r.published_at, r.id));
    return { items: await this.presenter.present(viewerId, page.items), nextCursor: page.nextCursor, pinned };
  }

  async drafts(authorId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<PostView>> {
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.post.findMany({
      where: {
        authorId, status: 'DRAFT', deletedAt: null,
        ...(c ? { OR: [{ createdAt: { lt: c.date } }, { createdAt: c.date, id: { lt: c.id } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
      select: { id: true, createdAt: true },
    });
    const page = toPage(rows, limit, (r) => r.id, (r) => timeCursor(r.createdAt, r.id));
    return { items: await this.presenter.present(authorId, page.items), nextCursor: page.nextCursor };
  }

  // ─── Pin / repost / share / save ───────────────────────────────────────────

  async pin(authorId: string, postId: string, pinned: boolean): Promise<PostView> {
    await this.prisma.$transaction(async (tx) => {
      const post = await this.ownPost(tx, authorId, postId);
      if (post.status !== 'PUBLISHED') throw AppError.badRequest('Only published posts can be pinned');
      if (pinned) await tx.post.updateMany({ where: { authorId, isPinned: true }, data: { isPinned: false } });
      await tx.post.update({ where: { id: postId }, data: { isPinned: pinned } });
    });
    return this.view(authorId, postId);
  }

  /** Plain repost. Only PUBLIC posts can be reposted, so a repost never widens an original's audience. */
  async repost(userId: string, postId: string): Promise<PostView> {
    let repostId: string;
    let notify: string[];
    try {
      ({ repostId, notify } = await this.prisma.$transaction(async (tx) => {
        await this.assertRepostable(tx, userId, postId);
        const repost = await tx.post.create({
          data: { authorId: userId, repostOfId: postId, audience: 'PUBLIC', status: 'PUBLISHED', publishedAt: new Date() },
          select: { id: true },
        });
        await tx.userProfile.update({ where: { userId }, data: { postsCount: { increment: 1 } } });
        const items = await this.onReposted(tx, userId, repost.id, postId);
        return { repostId: repost.id, notify: await this.notifications.write(tx, items) };
      }));
    } catch (error) {
      if (isUniqueViolation(error, 'repost_of_id')) throw AppError.conflict('You already reposted this post');
      throw error;
    }
    await this.notifications.dispatch(notify);
    await this.afterPublish(userId, repostId);
    return this.view(userId, repostId);
  }

  async undoRepost(userId: string, postId: string): Promise<void> {
    // feed_entries rows cascade with the hard delete.
    await this.prisma.$transaction(async (tx) => {
      const repost = await tx.post.findFirst({ where: { authorId: userId, repostOfId: postId, deletedAt: null } });
      if (!repost) return;
      if (repost.text || (await tx.postMedia.count({ where: { postId: repost.id } }))) {
        throw AppError.badRequest('This is a quote post; delete it instead');
      }
      // Plain reposts are hard-deleted so the user can repost again later.
      await tx.post.delete({ where: { id: repost.id } });
      await tx.$executeRaw`UPDATE user_profiles SET posts_count = GREATEST(posts_count - 1, 0) WHERE user_id = ${userId}::uuid`;
      await tx.$executeRaw`UPDATE posts SET repost_count = GREATEST(repost_count - 1, 0) WHERE id = ${postId}::uuid`;
      const original = await tx.post.findUnique({ where: { id: postId }, select: { authorId: true } });
      if (original) await this.notifications.retract(tx, original.authorId, `REPOST:${postId}:${userId}`);
    });
  }

  async share(userId: string, postId: string, channel: string): Promise<{ shares: number }> {
    if (!(await this.relationships.canViewPost(userId, postId))) throw AppError.notFound('Post');
    const post = await this.prisma.$transaction(async (tx) => {
      await tx.postShare.create({ data: { postId, userId, channel } });
      return tx.post.update({ where: { id: postId }, data: { shareCount: { increment: 1 } }, select: { shareCount: true } });
    });
    await this.analytics.add('event', { userId, type: 'post.share', entityId: postId, properties: { channel } });
    return { shares: post.shareCount };
  }

  async save(userId: string, postId: string, saved: boolean): Promise<{ saved: boolean }> {
    if (saved && !(await this.relationships.canViewPost(userId, postId))) throw AppError.notFound('Post');
    await this.prisma.$transaction(async (tx) => {
      if (saved) {
        const n = await tx.$executeRaw`INSERT INTO saved_posts (user_id, post_id, created_at) VALUES (${userId}::uuid, ${postId}::uuid, now()) ON CONFLICT DO NOTHING`;
        if (n) await tx.post.update({ where: { id: postId }, data: { saveCount: { increment: 1 } } });
      } else {
        const { count } = await tx.savedPost.deleteMany({ where: { userId, postId } });
        if (count) await tx.$executeRaw`UPDATE posts SET save_count = GREATEST(save_count - 1, 0) WHERE id = ${postId}::uuid`;
      }
    });
    return { saved };
  }

  async savedPosts(userId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<PostView>> {
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.$queryRaw<Array<{ id: string; saved_at: Date }>>`
      SELECT p.id, s.created_at AS saved_at FROM saved_posts s JOIN posts p ON p.id = s.post_id
      WHERE s.user_id = ${userId}::uuid AND ${this.relationships.visiblePostSql(userId)}
        ${c ? Prisma.sql`AND (s.created_at, p.id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
      ORDER BY s.created_at DESC, p.id DESC LIMIT ${limit + 1}`;
    const page = toPage(rows, limit, (r) => r.id, (r) => timeCursor(r.saved_at, r.id));
    return { items: await this.presenter.present(userId, page.items), nextCursor: page.nextCursor };
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  private async view(viewerId: string, postId: string): Promise<PostView> {
    const view = await this.presenter.presentOne(viewerId, postId);
    if (!view) throw AppError.notFound('Post');
    return view;
  }

  private async ownPost(tx: Tx, authorId: string, postId: string) {
    const post = await tx.post.findFirst({ where: { id: postId, authorId, deletedAt: null } });
    if (!post) throw AppError.notFound('Post');
    return post;
  }

  private async assertRepostable(tx: Tx, userId: string, postId: string) {
    const original = await tx.post.findFirst({ where: { id: postId, deletedAt: null, status: 'PUBLISHED' }, select: { authorId: true, audience: true, repostOfId: true, text: true } });
    if (!original || !(await this.relationships.canViewPost(userId, postId, tx))) throw AppError.notFound('Post');
    if (original.authorId === userId) throw AppError.badRequest('You cannot repost your own post');
    if (original.audience !== 'PUBLIC') throw new AppError('FORBIDDEN', 'Only public posts can be reposted', HttpStatus.FORBIDDEN);
    if (original.repostOfId && !original.text) throw AppError.badRequest('Repost the original post instead');
  }

  private async attachMedia(tx: Tx, authorId: string, postId: string, mediaIds: string[]) {
    if (mediaIds.length === 0) return;
    const assets = await tx.mediaAsset.findMany({
      where: { id: { in: mediaIds }, ownerId: authorId, purpose: 'POST', deletedAt: null, status: { in: ['PROCESSING', 'READY'] }, postMedia: null },
      select: { id: true },
    });
    if (assets.length !== mediaIds.length) throw AppError.badRequest('One or more media items are missing, not uploaded, or already used');
    await tx.postMedia.createMany({ data: mediaIds.map((mediaId, position) => ({ postId, mediaId, position })) });
  }

  /** Counters, hashtags and mentions for a post that just became PUBLISHED. Returns notifications to write. */
  private async onPublished(tx: Tx, authorId: string, postId: string, text: string | null): Promise<NewNotification[]> {
    await tx.userProfile.update({ where: { userId: authorId }, data: { postsCount: { increment: 1 } } });
    return this.syncEntities(tx, authorId, postId, null, text);
  }

  private async onReposted(tx: Tx, userId: string, repostId: string, originalId: string): Promise<NewNotification[]> {
    const original = await tx.post.update({ where: { id: originalId }, data: { repostCount: { increment: 1 } }, select: { authorId: true } });
    return [{ recipientId: original.authorId, actorId: userId, type: 'REPOST', postId: repostId, dedupeKey: `REPOST:${originalId}:${userId}` }];
  }

  /** Diff hashtags/mentions between old and new text. New mentions of users who can see the post get notified. */
  private async syncEntities(tx: Tx, authorId: string, postId: string, oldText: string | null, newText: string | null): Promise<NewNotification[]> {
    const before = extractEntities(oldText);
    const after = extractEntities(newText);
    await this.syncHashtags(tx, postId, before.hashtags, after.hashtags);

    await tx.mention.deleteMany({ where: { postId } });
    if (after.mentions.length === 0) return [];
    const users = await tx.userProfile.findMany({ where: { username: { in: after.mentions }, user: { status: 'ACTIVE' } }, select: { userId: true } });
    const mentioned = users.map((u) => u.userId).filter((id) => id !== authorId);
    if (mentioned.length === 0) return [];
    await tx.mention.createMany({ data: mentioned.map((mentionedUserId) => ({ postId, mentionedUserId })), skipDuplicates: true });
    const visible: string[] = [];
    for (const id of mentioned) if (await this.relationships.canViewPost(id, postId, tx)) visible.push(id);
    return visible.map((recipientId) => ({ recipientId, actorId: authorId, type: 'MENTION' as const, postId, dedupeKey: `MENTION:post:${postId}` }));
  }

  private async syncHashtags(tx: Tx, postId: string, before: string[], after: string[]) {
    const removed = before.filter((t) => !after.includes(t));
    const added = after.filter((t) => !before.includes(t));
    if (removed.length) {
      const tags = await tx.hashtag.findMany({ where: { tag: { in: removed } }, select: { id: true } });
      const { count } = await tx.postHashtag.deleteMany({ where: { postId, hashtagId: { in: tags.map((t) => t.id) } } });
      if (count) await tx.$executeRaw`UPDATE hashtags SET post_count = GREATEST(post_count - 1, 0) WHERE id = ANY(${tags.map((t) => t.id)}::uuid[])`;
    }
    for (const tag of added) {
      const h = await tx.hashtag.upsert({ where: { tag }, create: { tag }, update: {}, select: { id: true } });
      const n = await tx.$executeRaw`INSERT INTO post_hashtags (post_id, hashtag_id, created_at) VALUES (${postId}::uuid, ${h.id}::uuid, now()) ON CONFLICT DO NOTHING`;
      if (n) await tx.hashtag.update({ where: { id: h.id }, data: { postCount: { increment: 1 }, lastUsedAt: new Date() } });
    }
  }

  private async afterPublish(authorId: string, postId: string) {
    // The author should see their own post immediately, before the fan-out job runs.
    await this.redis.del(followingCacheKey(authorId)).catch(() => undefined);
    await this.feedQueue.add('fanout', { postId }, { jobId: `fo-${postId}` });
    await this.analytics.add('event', { userId: authorId, type: 'post.create', entityId: postId });
  }
}
