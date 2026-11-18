import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { MediaCleanup } from '../media/media-cleanup';
import { NotificationWriter } from '../notifications/notification-writer.service';
import { sweepUndispatched } from '../notifications/notification.processor';
import { PrismaService } from '../prisma/prisma.service';
import { Q } from '../queues/queues';

const FEED_KEEP_PER_USER = 1000;
const FEED_MAX_AGE_DAYS = 90;
/** Posts/comments touched (counter updates bump updated_at) within this window are re-verified nightly. */
const RECONCILE_DAYS = 3;

/** Recurring maintenance. Every job is idempotent and bounded, so overlapping runs are harmless. */
@Processor(Q.cleanup, { concurrency: 1 })
export class CleanupProcessor extends WorkerHost {
  private readonly logger = new Logger(CleanupProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly media: MediaCleanup,
    private readonly notifications: NotificationWriter,
  ) {
    super();
  }

  async process(job: Job): Promise<unknown> {
    switch (job.name) {
      case 'media-sweep':
        return this.media.sweep();
      case 'notification-sweep':
        return { redispatched: await sweepUndispatched(this.prisma, (ids) => this.notifications.dispatch(ids)) };
      case 'counter-reconcile':
        return this.reconcileCounters();
      case 'feed-trim':
        return this.trimFeeds();
      case 'follow-requests':
        return this.prisma.followRequest.deleteMany({ where: { status: { not: 'PENDING' }, updatedAt: { lt: new Date(Date.now() - 30 * 86400_000) } } });
      default:
        throw new Error(`unknown cleanup job ${job.name}`);
    }
  }

  /**
   * Recomputes denormalised counters from the source tables and fixes any drift (which should never
   * happen, since counters change transactionally — this is the safety net). Posts and comments are
   * limited to recently updated rows so the job's cost tracks activity, not total content. Returns rows corrected.
   */
  async reconcileCounters(): Promise<Record<string, number>> {
    const fixed: Record<string, number> = {};
    fixed.posts = await this.prisma.$executeRaw`
      WITH truth AS (
        SELECT p.id,
          (SELECT count(*) FROM post_reactions r WHERE r.post_id = p.id AND r.type = 'LIKE')::int AS likes,
          (SELECT count(*) FROM post_reactions r WHERE r.post_id = p.id AND r.type = 'DISLIKE')::int AS dislikes,
          (SELECT count(*) FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL)::int AS comments,
          (SELECT count(*) FROM posts rp WHERE rp.repost_of_id = p.id AND rp.deleted_at IS NULL AND rp.status = 'PUBLISHED')::int AS reposts,
          (SELECT count(*) FROM saved_posts s WHERE s.post_id = p.id)::int AS saves
        FROM posts p WHERE p.deleted_at IS NULL AND p.updated_at > now() - make_interval(days => ${RECONCILE_DAYS}::int)
      )
      UPDATE posts p SET like_count = t.likes, dislike_count = t.dislikes, comment_count = t.comments, repost_count = t.reposts, save_count = t.saves
      FROM truth t
      WHERE p.id = t.id AND (p.like_count, p.dislike_count, p.comment_count, p.repost_count, p.save_count) IS DISTINCT FROM (t.likes, t.dislikes, t.comments, t.reposts, t.saves)`;
    fixed.comments = await this.prisma.$executeRaw`
      WITH truth AS (
        SELECT c.id,
          (SELECT count(*) FROM comment_reactions r WHERE r.comment_id = c.id AND r.type = 'LIKE')::int AS likes,
          (SELECT count(*) FROM comment_reactions r WHERE r.comment_id = c.id AND r.type = 'DISLIKE')::int AS dislikes,
          (SELECT count(*) FROM comments x WHERE x.root_id = c.id AND x.deleted_at IS NULL)::int AS replies
        FROM comments c WHERE c.updated_at > now() - make_interval(days => ${RECONCILE_DAYS}::int)
      )
      UPDATE comments c SET like_count = t.likes, dislike_count = t.dislikes, reply_count = t.replies FROM truth t
      WHERE c.id = t.id AND (c.like_count, c.dislike_count, c.reply_count) IS DISTINCT FROM (t.likes, t.dislikes, t.replies)`;
    fixed.profiles = await this.prisma.$executeRaw`
      WITH truth AS (
        SELECT up.user_id,
          (SELECT count(*) FROM follows f WHERE f.followee_id = up.user_id)::int AS followers,
          (SELECT count(*) FROM follows f WHERE f.follower_id = up.user_id)::int AS following,
          (SELECT count(*) FROM posts p WHERE p.author_id = up.user_id AND p.deleted_at IS NULL AND p.status = 'PUBLISHED')::int AS posts
        FROM user_profiles up
      )
      UPDATE user_profiles up SET followers_count = t.followers, following_count = t.following, posts_count = t.posts FROM truth t
      WHERE up.user_id = t.user_id AND (up.followers_count, up.following_count, up.posts_count) IS DISTINCT FROM (t.followers, t.following, t.posts)`;
    fixed.hashtags = await this.prisma.$executeRaw`
      WITH truth AS (
        SELECT h.id, (SELECT count(*) FROM post_hashtags ph JOIN posts p ON p.id = ph.post_id
                      WHERE ph.hashtag_id = h.id AND p.deleted_at IS NULL AND p.status = 'PUBLISHED')::int AS n
        FROM hashtags h
      )
      UPDATE hashtags h SET post_count = t.n FROM truth t WHERE h.id = t.id AND h.post_count <> t.n`;
    const total = Object.values(fixed).reduce((a, b) => a + b, 0);
    if (total) this.logger.warn({ fixed }, 'counter drift corrected');
    return fixed;
  }

  /** Keeps feed_entries bounded: newest FEED_KEEP_PER_USER per user, nothing older than FEED_MAX_AGE_DAYS. */
  async trimFeeds(): Promise<{ removed: number }> {
    const removed = await this.prisma.$executeRaw`
      DELETE FROM feed_entries fe USING (
        SELECT user_id, post_id FROM (
          SELECT user_id, post_id, sort_at, row_number() OVER (PARTITION BY user_id ORDER BY sort_at DESC) AS rn FROM feed_entries
        ) ranked
        WHERE rn > ${FEED_KEEP_PER_USER}::int OR sort_at < now() - make_interval(days => ${FEED_MAX_AGE_DAYS}::int)
      ) old
      WHERE fe.user_id = old.user_id AND fe.post_id = old.post_id`;
    return { removed };
  }
}

/** Registers recurring jobs (idempotent upsert, so every worker instance can call it on boot). */
@Injectable()
export class Schedules implements OnApplicationBootstrap {
  private readonly logger = new Logger(Schedules.name);

  constructor(
    @InjectQueue(Q.cleanup) private readonly cleanup: Queue,
    @InjectQueue(Q.search) private readonly search: Queue,
    @InjectQueue(Q.analytics) private readonly analytics: Queue,
  ) {}

  async onApplicationBootstrap() {
    const every = (ms: number) => ({ every: ms });
    await this.cleanup.upsertJobScheduler('notification-sweep', every(60_000), { name: 'notification-sweep' });
    await this.cleanup.upsertJobScheduler('media-sweep', every(3_600_000), { name: 'media-sweep' });
    await this.cleanup.upsertJobScheduler('counter-reconcile', { pattern: '17 3 * * *' }, { name: 'counter-reconcile' });
    await this.cleanup.upsertJobScheduler('feed-trim', { pattern: '47 3 * * *' }, { name: 'feed-trim' });
    await this.cleanup.upsertJobScheduler('follow-requests', { pattern: '7 4 * * *' }, { name: 'follow-requests' });
    await this.search.upsertJobScheduler('trending-hashtags', every(10 * 60_000), { name: 'trending-hashtags' });
    await this.analytics.upsertJobScheduler('aggregate-daily', every(15 * 60_000), { name: 'aggregate', data: { period: 'day' } });
    await this.analytics.upsertJobScheduler('aggregate-monthly', { pattern: '30 2 * * *' }, { name: 'aggregate', data: { period: 'month' } });
    this.logger.log('job schedules registered');
  }
}
