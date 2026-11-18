import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { Prisma, ReactionType } from '@prisma/client';
import { Queue } from 'bullmq';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, Page, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { RelationshipService } from '../graph/relationship.service';
import { NotificationWriter } from '../notifications/notification-writer.service';
import { PrismaService, Tx } from '../prisma/prisma.service';
import { AnalyticsEventJob, Q } from '../queues/queues';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';

export type Target = 'post' | 'comment';

export interface ReactionSummary {
  likes: number;
  dislikes: number;
  mine: ReactionType | null;
}

const COUNTER: Record<ReactionType, 'like_count' | 'dislike_count'> = { LIKE: 'like_count', DISLIKE: 'dislike_count' };

/**
 * Post and comment reactions. One reaction per (user, target) — enforced by the primary key — and the
 * denormalised counters change in the same transaction as the reaction row. A transaction-scoped
 * advisory lock on (target, user) serialises concurrent taps from the same user, so like/unlike/switch
 * races can never double count.
 */
@Injectable()
export class ReactionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly notifications: NotificationWriter,
    private readonly users: UserPresenter,
    @InjectQueue(Q.analytics) private readonly analytics: Queue<AnalyticsEventJob>,
  ) {}

  async set(target: Target, targetId: string, userId: string, type: ReactionType | null): Promise<ReactionSummary> {
    const { notify, summary } = await this.prisma.$transaction(async (tx) => {
      const owner = await this.assertVisible(tx, target, targetId, userId);
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`${target}:${targetId}:${userId}`}, 0))`;
      const table = Prisma.raw(target === 'post' ? 'post_reactions' : 'comment_reactions');
      const parentTable = Prisma.raw(target === 'post' ? 'posts' : 'comments');
      const fk = Prisma.raw(target === 'post' ? 'post_id' : 'comment_id');

      const [existing] = await tx.$queryRaw<Array<{ type: ReactionType }>>`
        SELECT type FROM ${table} WHERE ${fk} = ${targetId}::uuid AND user_id = ${userId}::uuid`;
      const previous = existing?.type ?? null;
      const notify: string[] = [];

      if (previous !== type) {
        if (previous) {
          await tx.$executeRaw`DELETE FROM ${table} WHERE ${fk} = ${targetId}::uuid AND user_id = ${userId}::uuid`;
          const col = Prisma.raw(COUNTER[previous]);
          await tx.$executeRaw`UPDATE ${parentTable} SET ${col} = GREATEST(${col} - 1, 0) WHERE id = ${targetId}::uuid`;
        }
        if (type) {
          await tx.$executeRaw`
            INSERT INTO ${table} (${fk}, user_id, type, created_at, updated_at)
            VALUES (${targetId}::uuid, ${userId}::uuid, ${type}::"ReactionType", now(), now())`;
          const col = Prisma.raw(COUNTER[type]);
          await tx.$executeRaw`UPDATE ${parentTable} SET ${col} = ${col} + 1 WHERE id = ${targetId}::uuid`;
        }
        const dedupeKey = `${target === 'post' ? 'POST_REACTION' : 'COMMENT_REACTION'}:${targetId}:${userId}`;
        if (type === 'LIKE') {
          // Only likes notify; dislikes are private signals.
          notify.push(...(await this.notifications.write(tx, [{
            recipientId: owner.authorId,
            actorId: userId,
            type: target === 'post' ? 'POST_REACTION' : 'COMMENT_REACTION',
            dedupeKey,
            postId: owner.postId,
            commentId: target === 'comment' ? targetId : undefined,
            data: { reaction: type },
          }])));
        } else if (previous === 'LIKE') {
          await this.notifications.retract(tx, owner.authorId, dedupeKey);
        }
      }
      return { notify, summary: await this.summaryTx(tx, target, targetId, userId) };
    });
    await this.notifications.dispatch(notify);
    if (type) await this.analytics.add('event', { userId, type: `${target}.reaction`, entityId: targetId, properties: { reaction: type } });
    return summary;
  }

  async summary(target: Target, targetId: string, userId: string): Promise<ReactionSummary> {
    await this.assertVisible(this.prisma, target, targetId, userId);
    return this.summaryTx(this.prisma, target, targetId, userId);
  }

  /** Who reacted (newest first). Blocked users are excluded both ways. */
  async reactors(target: Target, targetId: string, viewerId: string, type: ReactionType | undefined, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<UserSummary & { reaction: ReactionType; reactedAt: string }>> {
    await this.assertVisible(this.prisma, target, targetId, viewerId);
    const c = parseTimeCursor(cursor);
    const table = Prisma.raw(target === 'post' ? 'post_reactions' : 'comment_reactions');
    const fk = Prisma.raw(target === 'post' ? 'post_id' : 'comment_id');
    const rows = await this.prisma.$queryRaw<Array<{ user_id: string; type: ReactionType; created_at: Date }>>`
      SELECT r.user_id, r.type, r.created_at FROM ${table} r
      WHERE r.${fk} = ${targetId}::uuid
        ${type ? Prisma.sql`AND r.type = ${type}::"ReactionType"` : Prisma.empty}
        ${c ? Prisma.sql`AND (r.created_at, r.user_id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`r.user_id`, viewerId)}
      ORDER BY r.created_at DESC, r.user_id DESC LIMIT ${limit + 1}`;
    const summaries = await this.users.summaries(rows.map((r) => r.user_id));
    const page = toPage(rows, limit, (r) => r, (r) => timeCursor(r.created_at, r.user_id));
    return {
      items: page.items.flatMap((r) => {
        const s = summaries.get(r.user_id);
        return s ? [{ ...s, reaction: r.type, reactedAt: r.created_at.toISOString() }] : [];
      }),
      nextCursor: page.nextCursor,
    };
  }

  private async summaryTx(db: Tx | PrismaService, target: Target, targetId: string, userId: string): Promise<ReactionSummary> {
    if (target === 'post') {
      const [p, mine] = await Promise.all([
        db.post.findUniqueOrThrow({ where: { id: targetId }, select: { likeCount: true, dislikeCount: true } }),
        db.postReaction.findUnique({ where: { postId_userId: { postId: targetId, userId } }, select: { type: true } }),
      ]);
      return { likes: p.likeCount, dislikes: p.dislikeCount, mine: mine?.type ?? null };
    }
    const [c, mine] = await Promise.all([
      db.comment.findUniqueOrThrow({ where: { id: targetId }, select: { likeCount: true, dislikeCount: true } }),
      db.commentReaction.findUnique({ where: { commentId_userId: { commentId: targetId, userId } }, select: { type: true } }),
    ]);
    return { likes: c.likeCount, dislikes: c.dislikeCount, mine: mine?.type ?? null };
  }

  /** Returns the content owner. 404 when the target is deleted or the viewer cannot see it. */
  private async assertVisible(db: Tx | PrismaService, target: Target, targetId: string, userId: string): Promise<{ authorId: string; postId: string }> {
    if (target === 'post') {
      const post = await db.post.findFirst({ where: { id: targetId, deletedAt: null, status: 'PUBLISHED' }, select: { authorId: true } });
      if (!post || !(await this.relationships.canViewPost(userId, targetId, db))) throw AppError.notFound('Post');
      return { authorId: post.authorId, postId: targetId };
    }
    const comment = await db.comment.findFirst({ where: { id: targetId, deletedAt: null }, select: { authorId: true, postId: true } });
    if (!comment || !(await this.relationships.canViewPost(userId, comment.postId, db))) throw AppError.notFound('Comment');
    if (await this.relationships.isBlockedEitherWay(userId, comment.authorId, db)) throw AppError.notFound('Comment');
    return comment;
  }
}
