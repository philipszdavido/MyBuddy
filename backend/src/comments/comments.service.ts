import { InjectQueue } from '@nestjs/bullmq';
import { Injectable } from '@nestjs/common';
import { Prisma, ReactionType, UserRole } from '@prisma/client';
import { Queue } from 'bullmq';
import { AuditService } from '../common/audit.service';
import { AuthContext } from '../common/decorators/auth.decorators';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, Page, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { extractEntities } from '../content/text-entities';
import { RelationshipService } from '../graph/relationship.service';
import { NewNotification, NotificationWriter } from '../notifications/notification-writer.service';
import { isUniqueViolation, PrismaService, Tx } from '../prisma/prisma.service';
import { AnalyticsEventJob, Q } from '../queues/queues';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';

export const MAX_COMMENT_LENGTH = 1000;

export interface CommentView {
  id: string;
  postId: string;
  /** null for top-level comments */
  parentId: string | null;
  rootId: string | null;
  author: UserSummary | null;
  /** null when deleted: the thread keeps a "comment deleted" placeholder so replies keep their context */
  text: string | null;
  deleted: boolean;
  counts: { likes: number; dislikes: number; replies: number };
  viewer: { reaction: ReactionType | null; canEdit: boolean; canDelete: boolean };
  editedAt: string | null;
  createdAt: string;
}

const STAFF: UserRole[] = ['MODERATOR', 'ADMIN'];

type CommentRow = {
  id: string; postId: string; parentId: string | null; rootId: string | null; authorId: string; text: string;
  likeCount: number; dislikeCount: number; replyCount: number; editedAt: Date | null; createdAt: Date; deletedAt: Date | null;
};

@Injectable()
export class CommentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly notifications: NotificationWriter,
    private readonly users: UserPresenter,
    private readonly audit: AuditService,
    @InjectQueue(Q.analytics) private readonly analytics: Queue<AnalyticsEventJob>,
  ) {}

  async create(authorId: string, postId: string, text: string, parentId?: string, clientId?: string): Promise<CommentView> {
    const body = text.trim();
    if (!body) throw AppError.badRequest('Comment text is required');
    if (clientId) {
      const existing = await this.prisma.comment.findUnique({ where: { authorId_clientId: { authorId, clientId } } });
      if (existing) return (await this.present(authorId, [existing], null))[0];
    }
    let created: { comment: CommentRow; notify: string[]; postAuthorId: string };
    try {
      created = await this.prisma.$transaction(async (tx) => {
        const post = await tx.post.findFirst({ where: { id: postId, deletedAt: null, status: 'PUBLISHED' }, select: { authorId: true } });
        if (!post || !(await this.relationships.canViewPost(authorId, postId, tx))) throw AppError.notFound('Post');

        let parent: { id: string; rootId: string | null; authorId: string } | null = null;
        if (parentId) {
          parent = await tx.comment.findFirst({ where: { id: parentId, postId, deletedAt: null }, select: { id: true, rootId: true, authorId: true } });
          if (!parent) throw AppError.notFound('Comment');
          if (await this.relationships.isBlockedEitherWay(authorId, parent.authorId, tx)) throw AppError.notFound('Comment');
        }
        const rootId = parent ? parent.rootId ?? parent.id : null;
        const comment = await tx.comment.create({ data: { postId, authorId, text: body, parentId: parent?.id, rootId, clientId } });
        await tx.post.update({ where: { id: postId }, data: { commentCount: { increment: 1 } } });
        if (rootId) await tx.comment.update({ where: { id: rootId }, data: { replyCount: { increment: 1 } } });

        const items: NewNotification[] = [];
        if (parent) {
          items.push({ recipientId: parent.authorId, actorId: authorId, type: 'COMMENT_REPLY', postId, commentId: comment.id, dedupeKey: `COMMENT_REPLY:${comment.id}` });
        }
        if (!parent || parent.authorId !== post.authorId) {
          items.push({ recipientId: post.authorId, actorId: authorId, type: 'COMMENT', postId, commentId: comment.id, dedupeKey: `COMMENT:${comment.id}` });
        }
        items.push(...(await this.mentions(tx, authorId, postId, comment.id, body)));
        return { comment, notify: await this.notifications.write(tx, items), postAuthorId: post.authorId };
      });
    } catch (error) {
      if (clientId && isUniqueViolation(error, 'client_id')) {
        const existing = await this.prisma.comment.findUniqueOrThrow({ where: { authorId_clientId: { authorId, clientId } } });
        return (await this.present(authorId, [existing], null))[0];
      }
      throw error;
    }
    await this.notifications.dispatch(created.notify);
    await this.analytics.add('event', { userId: authorId, type: 'comment.create', entityId: postId });
    return (await this.present(authorId, [created.comment], created.postAuthorId))[0];
  }

  async update(authorId: string, commentId: string, text: string): Promise<CommentView> {
    const body = text.trim();
    if (!body) throw AppError.badRequest('Comment text is required');
    const { comment, notify } = await this.prisma.$transaction(async (tx) => {
      const existing = await tx.comment.findFirst({ where: { id: commentId, authorId, deletedAt: null } });
      if (!existing) throw AppError.notFound('Comment');
      const comment = await tx.comment.update({ where: { id: commentId }, data: { text: body, editedAt: new Date() } });
      const before = new Set(extractEntities(existing.text).mentions);
      const added = extractEntities(body).mentions.filter((m) => !before.has(m));
      const items = added.length ? await this.mentions(tx, authorId, comment.postId, commentId, added.map((m) => `@${m}`).join(' ')) : [];
      return { comment, notify: await this.notifications.write(tx, items) };
    });
    await this.notifications.dispatch(notify);
    return (await this.present(authorId, [comment], null))[0];
  }

  /** Author, post author (moderating their own thread) or staff may delete. */
  async remove(actor: AuthContext, commentId: string): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      const comment = await tx.comment.findFirst({ where: { id: commentId, deletedAt: null }, include: { post: { select: { authorId: true } } } });
      if (!comment) throw AppError.notFound('Comment');
      const allowed = comment.authorId === actor.userId || comment.post.authorId === actor.userId || STAFF.includes(actor.role);
      if (!allowed) throw AppError.notFound('Comment');
      await this.softDelete(tx, comment);
      if (STAFF.includes(actor.role) && comment.authorId !== actor.userId && comment.post.authorId !== actor.userId) {
        await this.audit.record({ actorId: actor.userId, action: 'comment.remove', targetType: 'comment', targetId: commentId }, tx);
      }
    });
  }

  async softDelete(tx: Tx, comment: { id: string; postId: string; rootId: string | null }): Promise<void> {
    await tx.comment.update({ where: { id: comment.id }, data: { deletedAt: new Date() } });
    await tx.$executeRaw`UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = ${comment.postId}::uuid`;
    if (comment.rootId) await tx.$executeRaw`UPDATE comments SET reply_count = GREATEST(reply_count - 1, 0) WHERE id = ${comment.rootId}::uuid`;
    await tx.mention.deleteMany({ where: { commentId: comment.id } });
    await tx.notification.deleteMany({ where: { commentId: comment.id, readAt: null } });
  }

  /** Post id of a comment (for POST /comments/:id/replies). */
  async postOf(commentId: string): Promise<string> {
    const c = await this.prisma.comment.findFirst({ where: { id: commentId, deletedAt: null }, select: { postId: true } });
    if (!c) throw AppError.notFound('Comment');
    return c.postId;
  }

  /** Top-level comments, newest first. Deleted comments with replies remain as placeholders. */
  async list(viewerId: string, postId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<CommentView>> {
    const postAuthorId = await this.assertPostVisible(viewerId, postId);
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.$queryRaw<CommentRow[]>`
      SELECT ${this.columns()} FROM comments c
      WHERE c.post_id = ${postId}::uuid AND c.root_id IS NULL
        AND (c.deleted_at IS NULL OR c.reply_count > 0)
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`c.author_id`, viewerId)}
        ${c ? Prisma.sql`AND (c.created_at, c.id) < (${c.date}, ${c.id}::uuid)` : Prisma.empty}
      ORDER BY c.created_at DESC, c.id DESC LIMIT ${limit + 1}`;
    const page = toPage(rows, limit, (r) => r, (r) => timeCursor(r.createdAt, r.id));
    return { items: await this.present(viewerId, page.items, postAuthorId), nextCursor: page.nextCursor };
  }

  /** Replies in a thread, oldest first (reading order). */
  async replies(viewerId: string, rootId: string, cursor?: string, limit = DEFAULT_PAGE): Promise<Page<CommentView>> {
    const root = await this.prisma.comment.findUnique({ where: { id: rootId }, select: { postId: true, rootId: true } });
    if (!root || root.rootId) throw AppError.notFound('Comment');
    const postAuthorId = await this.assertPostVisible(viewerId, root.postId);
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.$queryRaw<CommentRow[]>`
      SELECT ${this.columns()} FROM comments c
      WHERE c.root_id = ${rootId}::uuid AND c.deleted_at IS NULL
        AND ${this.relationships.blockedEitherWaySql(Prisma.sql`c.author_id`, viewerId)}
        ${c ? Prisma.sql`AND (c.created_at, c.id) > (${c.date}, ${c.id}::uuid)` : Prisma.empty}
      ORDER BY c.created_at ASC, c.id ASC LIMIT ${limit + 1}`;
    const page = toPage(rows, limit, (r) => r, (r) => timeCursor(r.createdAt, r.id));
    return { items: await this.present(viewerId, page.items, postAuthorId), nextCursor: page.nextCursor };
  }

  private columns() {
    return Prisma.sql`c.id, c.post_id AS "postId", c.parent_id AS "parentId", c.root_id AS "rootId", c.author_id AS "authorId",
      c.text, c.like_count AS "likeCount", c.dislike_count AS "dislikeCount", c.reply_count AS "replyCount",
      c.edited_at AS "editedAt", c.created_at AS "createdAt", c.deleted_at AS "deletedAt"`;
  }

  private async assertPostVisible(viewerId: string, postId: string): Promise<string> {
    const post = await this.prisma.post.findFirst({ where: { id: postId, deletedAt: null }, select: { authorId: true } });
    if (!post || !(await this.relationships.canViewPost(viewerId, postId))) throw AppError.notFound('Post');
    return post.authorId;
  }

  private async mentions(tx: Tx, authorId: string, postId: string, commentId: string, text: string): Promise<NewNotification[]> {
    const names = extractEntities(text).mentions;
    if (names.length === 0) return [];
    const users = await tx.userProfile.findMany({ where: { username: { in: names }, user: { status: 'ACTIVE' } }, select: { userId: true } });
    const out: NewNotification[] = [];
    for (const { userId } of users) {
      if (userId === authorId || !(await this.relationships.canViewPost(userId, postId, tx))) continue;
      await tx.mention.upsert({
        where: { commentId_mentionedUserId: { commentId, mentionedUserId: userId } },
        create: { commentId, mentionedUserId: userId },
        update: {},
      });
      out.push({ recipientId: userId, actorId: authorId, type: 'MENTION', postId, commentId, dedupeKey: `MENTION:comment:${commentId}` });
    }
    return out;
  }

  private async present(viewerId: string, rows: CommentRow[], postAuthorId: string | null): Promise<CommentView[]> {
    const live = rows.filter((r) => !r.deletedAt);
    const [authors, reactions, actor] = await Promise.all([
      this.users.summaries(live.map((r) => r.authorId)),
      this.prisma.commentReaction.findMany({ where: { userId: viewerId, commentId: { in: live.map((r) => r.id) } }, select: { commentId: true, type: true } }),
      this.prisma.user.findUnique({ where: { id: viewerId }, select: { role: true } }),
    ]);
    const mine = new Map(reactions.map((r) => [r.commentId, r.type]));
    const staff = actor ? STAFF.includes(actor.role) : false;
    return rows.map((r) => {
      const deleted = !!r.deletedAt;
      return {
        id: r.id,
        postId: r.postId,
        parentId: r.parentId,
        rootId: r.rootId,
        author: deleted ? null : authors.get(r.authorId) ?? null,
        text: deleted ? null : r.text,
        deleted,
        counts: { likes: r.likeCount, dislikes: r.dislikeCount, replies: r.replyCount },
        viewer: {
          reaction: mine.get(r.id) ?? null,
          canEdit: !deleted && r.authorId === viewerId,
          canDelete: !deleted && (r.authorId === viewerId || postAuthorId === viewerId || staff),
        },
        editedAt: r.editedAt?.toISOString() ?? null,
        createdAt: r.createdAt.toISOString(),
      };
    });
  }
}
