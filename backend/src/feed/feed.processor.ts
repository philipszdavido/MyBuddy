import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { Job } from 'bullmq';
import type Redis from 'ioredis';
import type { Env } from '../config/env';
import { RelationshipService } from '../graph/relationship.service';
import { PrismaService } from '../prisma/prisma.service';
import { BackfillFollowJob, FanoutPostJob, Q, RetractPostJob, UnfollowJob } from '../queues/queues';
import { REDIS } from '../redis/redis.module';
import { followingCacheKey } from './feed.service';

const BATCH = 5000;
const BACKFILL_POSTS = 50;

/**
 * Feed distribution. Every job is idempotent (inserts are ON CONFLICT DO NOTHING; deletes are
 * re-evaluated against current visibility), so retries and duplicate jobs are harmless.
 */
@Processor(Q.feed, { concurrency: Number(process.env.WORKER_CONCURRENCY ?? 5) })
export class FeedProcessor extends WorkerHost {
  private readonly logger = new Logger(FeedProcessor.name);
  private readonly fanoutMax: number;

  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    @Inject(REDIS) private readonly redis: Redis,
    config: ConfigService<Env, true>,
  ) {
    super();
    this.fanoutMax = config.get('FEED_FANOUT_MAX_FOLLOWERS', { infer: true });
  }

  async process(job: Job): Promise<unknown> {
    switch (job.name) {
      case 'fanout':
        return this.fanout((job.data as FanoutPostJob).postId);
      case 'retract':
        return this.retract((job.data as RetractPostJob).postId);
      case 'backfill-follow':
        return this.backfill(job.data as BackfillFollowJob);
      case 'unfollow':
        return this.unfollow(job.data as UnfollowJob);
      default:
        throw new Error(`unknown feed job ${job.name}`);
    }
  }

  /**
   * Fan-out on write. The author's own feed always gets the post; contacts get CONTACTS and PUBLIC posts;
   * followers get FOLLOWERS and PUBLIC posts unless the author is "large" (> FEED_FANOUT_MAX_FOLLOWERS),
   * in which case followers pull the post at read time. Recipients are inserted in keyset batches.
   */
  async fanout(postId: string): Promise<{ recipients: number }> {
    const post = await this.prisma.post.findFirst({
      where: { id: postId, deletedAt: null, status: 'PUBLISHED' },
      select: { id: true, authorId: true, audience: true, publishedAt: true, author: { select: { profile: { select: { followersCount: true } } } } },
    });
    if (!post || !post.publishedAt) return { recipients: 0 };
    const sortAt = post.publishedAt;

    await this.prisma.$executeRaw`
      INSERT INTO feed_entries (user_id, post_id, author_id, reason, sort_at, created_at)
      VALUES (${post.authorId}::uuid, ${post.id}::uuid, ${post.authorId}::uuid, 'SELF', ${sortAt}, now())
      ON CONFLICT DO NOTHING`;
    let total = 1;
    const touched: string[] = [post.authorId];

    if (post.audience === 'CONTACTS' || post.audience === 'PUBLIC') {
      const n = await this.insertBatched(post, sortAt, 'CONTACT', (after) => Prisma.sql`
        SELECT cl.contact_id AS uid FROM contact_links cl WHERE cl.owner_id = ${post.authorId}::uuid AND cl.contact_id > ${after}::uuid
        ORDER BY cl.contact_id LIMIT ${BATCH}`, touched);
      total += n;
    }
    const large = (post.author.profile?.followersCount ?? 0) > this.fanoutMax;
    if ((post.audience === 'FOLLOWERS' || post.audience === 'PUBLIC') && !large) {
      const n = await this.insertBatched(post, sortAt, 'FOLLOW', (after) => Prisma.sql`
        SELECT f.follower_id AS uid FROM follows f WHERE f.followee_id = ${post.authorId}::uuid AND f.follower_id > ${after}::uuid
        ORDER BY f.follower_id LIMIT ${BATCH}`, touched);
      total += n;
    }
    await this.invalidate(touched);
    return { recipients: total };
  }

  private async insertBatched(
    post: { id: string; authorId: string },
    sortAt: Date,
    reason: 'CONTACT' | 'FOLLOW',
    page: (afterId: string) => Prisma.Sql,
    touched: string[],
  ): Promise<number> {
    let after = '00000000-0000-0000-0000-000000000000';
    let total = 0;
    for (;;) {
      const batch = await this.prisma.$queryRaw<Array<{ uid: string }>>`${page(after)}`;
      if (batch.length === 0) break;
      const ids = batch.map((b) => b.uid);
      // Visibility is checked per recipient in SQL, so blocked users never receive the entry.
      total += await this.prisma.$executeRaw`
        INSERT INTO feed_entries (user_id, post_id, author_id, reason, sort_at, created_at)
        SELECT r.uid, p.id, p.author_id, ${reason}::"FeedReason", ${sortAt}, now()
        FROM unnest(${ids}::uuid[]) AS r(uid) JOIN posts p ON p.id = ${post.id}::uuid
        WHERE ${this.relationships.visiblePostSql(Prisma.sql`r.uid`)}
        ON CONFLICT DO NOTHING`;
      touched.push(...ids);
      after = ids[ids.length - 1];
      if (batch.length < BATCH) break;
    }
    return total;
  }

  /** Post deleted or audience narrowed: drop entries the recipient may no longer see. */
  async retract(postId: string): Promise<{ removed: number }> {
    const users = await this.prisma.$queryRaw<Array<{ user_id: string }>>`
      DELETE FROM feed_entries fe USING posts p
      WHERE fe.post_id = ${postId}::uuid AND p.id = fe.post_id
        AND NOT ${this.relationships.visiblePostSql(Prisma.sql`fe.user_id`)}
      RETURNING fe.user_id`;
    await this.invalidate(users.map((u) => u.user_id));
    return { removed: users.length };
  }

  /** New follow/contact edge: copy the followee's recent visible posts into the follower's feed. */
  async backfill({ followerId, followeeId }: BackfillFollowJob): Promise<{ added: number }> {
    const added = await this.prisma.$executeRaw`
      INSERT INTO feed_entries (user_id, post_id, author_id, reason, sort_at, created_at)
      SELECT ${followerId}::uuid, p.id, p.author_id,
             CASE WHEN EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = ${followerId}::uuid AND f.followee_id = p.author_id)
                  THEN 'FOLLOW'::"FeedReason" ELSE 'CONTACT'::"FeedReason" END,
             p.published_at, now()
      FROM posts p
      WHERE p.author_id = ${followeeId}::uuid AND p.published_at IS NOT NULL
        AND ${this.relationships.visiblePostSql(followerId)}
      ORDER BY p.published_at DESC
      LIMIT ${BACKFILL_POSTS}
      ON CONFLICT DO NOTHING`;
    await this.invalidate([followerId]);
    return { added };
  }

  /** Edge removed (unfollow, block, contact removed): drop the author's posts the user can no longer see. */
  async unfollow({ followerId, followeeId }: UnfollowJob): Promise<{ removed: number }> {
    const removed = await this.prisma.$executeRaw`
      DELETE FROM feed_entries fe USING posts p
      WHERE fe.user_id = ${followerId}::uuid AND fe.author_id = ${followeeId}::uuid AND p.id = fe.post_id
        AND NOT ${this.relationships.visiblePostSql(followerId)}`;
    await this.invalidate([followerId]);
    return { removed };
  }

  private async invalidate(userIds: string[]) {
    for (let i = 0; i < userIds.length; i += 500) {
      const keys = userIds.slice(i, i + 500).map(followingCacheKey);
      if (keys.length) await this.redis.del(...keys).catch((e: unknown) => this.logger.warn(`cache invalidation failed: ${String(e)}`));
    }
  }
}
