import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job, Queue } from 'bullmq';
import { TokenVerifier } from '../auth/token-verifier';
import { AuditService } from '../common/audit.service';
import { MediaVariants } from '../media/media-presenter.service';
import { StorageService } from '../media/storage.service';
import { PrismaService } from '../prisma/prisma.service';
import { AccountDeletionJob, EmailJob, Q } from '../queues/queues';
import { RealtimePublisher } from '../realtime/realtime.publisher';

/**
 * Deletes an account and its data (App Store / GDPR requirement). Steps, each safe to repeat:
 *  1. R2: delete every object the user uploaded (before the rows that list the keys are gone).
 *  2. PostgreSQL, one transaction: repair counters on *other people's* content (likes, comments,
 *     reposts, saves, follower counts, hashtag counts), then delete the user row — foreign keys cascade
 *     to profile, posts, comments, reactions, follows, blocks, devices, messages, notifications, etc.
 *     Conversations stay for the other participants. Audit-log rows keep the id (no FK).
 *  3. Firebase Auth: delete the identity (last, so a failure earlier leaves the account recoverable).
 */
@Processor(Q.accountDeletion, { concurrency: 2 })
export class AccountDeletionProcessor extends WorkerHost {
  private readonly logger = new Logger(AccountDeletionProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly verifier: TokenVerifier,
    private readonly audit: AuditService,
    private readonly realtime: RealtimePublisher,
    @InjectQueue(Q.email) private readonly email: Queue<EmailJob>,
  ) {
    super();
  }

  async process(job: Job<AccountDeletionJob>): Promise<{ deletedObjects: number; deletedUser: boolean }> {
    const { userId, firebaseUid } = job.data;
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { status: true, email: true } });
    if (user && user.status !== 'DELETING') return { deletedObjects: 0, deletedUser: false }; // cancelled / not requested

    let deletedObjects = 0;
    if (user) {
      const assets = await this.prisma.mediaAsset.findMany({ where: { ownerId: userId }, select: { objectKey: true, variants: true } });
      const keys = assets.flatMap((a) => [a.objectKey, ...Object.values((a.variants ?? {}) as MediaVariants).flatMap((v) => (v?.key ? [v.key] : []))]);
      await this.storage.deleteMany(keys);
      deletedObjects = keys.length;
      await job.updateProgress(30);

      await this.prisma.$transaction(async (tx) => {
        const u = userId;
        // Reactions on other people's posts/comments.
        await tx.$executeRaw`UPDATE posts p SET like_count = GREATEST(p.like_count - r.n, 0)
          FROM (SELECT post_id, count(*)::int n FROM post_reactions WHERE user_id = ${u}::uuid AND type = 'LIKE' GROUP BY post_id) r WHERE p.id = r.post_id`;
        await tx.$executeRaw`UPDATE posts p SET dislike_count = GREATEST(p.dislike_count - r.n, 0)
          FROM (SELECT post_id, count(*)::int n FROM post_reactions WHERE user_id = ${u}::uuid AND type = 'DISLIKE' GROUP BY post_id) r WHERE p.id = r.post_id`;
        await tx.$executeRaw`UPDATE comments c SET like_count = GREATEST(c.like_count - r.n, 0)
          FROM (SELECT comment_id, count(*)::int n FROM comment_reactions WHERE user_id = ${u}::uuid AND type = 'LIKE' GROUP BY comment_id) r WHERE c.id = r.comment_id`;
        await tx.$executeRaw`UPDATE comments c SET dislike_count = GREATEST(c.dislike_count - r.n, 0)
          FROM (SELECT comment_id, count(*)::int n FROM comment_reactions WHERE user_id = ${u}::uuid AND type = 'DISLIKE' GROUP BY comment_id) r WHERE c.id = r.comment_id`;
        // Their live comments and replies on other people's posts/threads.
        await tx.$executeRaw`UPDATE posts p SET comment_count = GREATEST(p.comment_count - r.n, 0)
          FROM (SELECT post_id, count(*)::int n FROM comments WHERE author_id = ${u}::uuid AND deleted_at IS NULL GROUP BY post_id) r WHERE p.id = r.post_id`;
        await tx.$executeRaw`UPDATE comments c SET reply_count = GREATEST(c.reply_count - r.n, 0)
          FROM (SELECT root_id, count(*)::int n FROM comments WHERE author_id = ${u}::uuid AND deleted_at IS NULL AND root_id IS NOT NULL GROUP BY root_id) r WHERE c.id = r.root_id`;
        // Their reposts/quotes and saves of other posts.
        await tx.$executeRaw`UPDATE posts p SET repost_count = GREATEST(p.repost_count - r.n, 0)
          FROM (SELECT repost_of_id, count(*)::int n FROM posts WHERE author_id = ${u}::uuid AND deleted_at IS NULL AND status = 'PUBLISHED' AND repost_of_id IS NOT NULL GROUP BY repost_of_id) r WHERE p.id = r.repost_of_id`;
        await tx.$executeRaw`UPDATE posts p SET save_count = GREATEST(p.save_count - 1, 0) FROM saved_posts s WHERE s.user_id = ${u}::uuid AND p.id = s.post_id`;
        // Hashtag counts of their published posts.
        await tx.$executeRaw`UPDATE hashtags h SET post_count = GREATEST(h.post_count - r.n, 0)
          FROM (SELECT ph.hashtag_id, count(*)::int n FROM post_hashtags ph JOIN posts p ON p.id = ph.post_id
                WHERE p.author_id = ${u}::uuid AND p.deleted_at IS NULL AND p.status = 'PUBLISHED' GROUP BY ph.hashtag_id) r WHERE h.id = r.hashtag_id`;
        // Social graph counters.
        await tx.$executeRaw`UPDATE user_profiles up SET followers_count = GREATEST(up.followers_count - 1, 0) FROM follows f WHERE f.follower_id = ${u}::uuid AND up.user_id = f.followee_id`;
        await tx.$executeRaw`UPDATE user_profiles up SET following_count = GREATEST(up.following_count - 1, 0) FROM follows f WHERE f.followee_id = ${u}::uuid AND up.user_id = f.follower_id`;
        await tx.user.delete({ where: { id: u } });
        await this.audit.record({ actorId: u, action: 'account.deleted', targetType: 'user', targetId: u, metadata: { objects: deletedObjects } }, tx);
      }, { timeout: 120_000 });
      await job.updateProgress(80);
    }

    await this.verifier.deleteUser(firebaseUid);
    if (user?.email) await this.email.add('account-deleted', { to: user.email, template: 'account-deleted' });
    this.logger.log(`account ${userId} deleted`);
    return { deletedObjects, deletedUser: !!user };
  }
}
