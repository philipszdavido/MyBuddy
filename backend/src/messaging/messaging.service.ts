import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { ConversationKind, MessageType, Prisma } from '@prisma/client';
import type Redis from 'ioredis';
import { AppError } from '../common/errors/app-error';
import { decodeCursor, encodeCursor, Page } from '../common/pagination/cursor';
import { RelationshipService } from '../graph/relationship.service';
import { MediaPresenter, MediaView } from '../media/media-presenter.service';
import { NotificationWriter } from '../notifications/notification-writer.service';
import { isUniqueViolation, PrismaService, Tx } from '../prisma/prisma.service';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { REDIS } from '../redis/redis.module';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';

export const MAX_MESSAGE_LENGTH = 4000;
export const MAX_GROUP_SIZE = 50;
const EDIT_WINDOW_MS = 15 * 60_000;
const SEND_LIMIT = { count: 30, windowSeconds: 10 };

export interface SendMessageInput {
  clientId: string;
  text?: string;
  mediaIds?: string[];
  replyToId?: string;
}

export interface MessageView {
  id: string;
  clientId: string;
  conversationId: string;
  seq: number;
  sender: UserSummary | null;
  senderId: string;
  type: MessageType;
  text: string | null;
  media: MediaView[];
  replyTo: { id: string; senderId: string; text: string | null; type: MessageType; deleted: boolean } | null;
  reactions: Array<{ emoji: string; count: number; mine: boolean }>;
  editedAt: string | null;
  deleted: boolean;
  createdAt: string;
}

export interface ConversationView {
  id: string;
  kind: ConversationKind;
  title: string | null;
  /** phoneNumber is present only for participants in the viewer's matched contacts (numbers the viewer already has). */
  participants: Array<UserSummary & { role: string; lastReadSeq: number | null; lastDeliveredSeq: number | null; phoneNumber: string | null }>;
  lastMessage: MessageView | null;
  lastSeq: number;
  unreadCount: number;
  isRequest: boolean;
  mutedUntil: string | null;
  archived: boolean;
  lastMessageAt: string | null;
  createdAt: string;
}

const messageInclude = {
  attachments: { orderBy: { position: 'asc' as const }, include: { media: true } },
  reactions: { select: { emoji: true, userId: true } },
  replyTo: { select: { id: true, senderId: true, text: true, type: true, deletedAt: true } },
} satisfies Prisma.MessageInclude;

type MessageRow = Prisma.MessageGetPayload<{ include: typeof messageInclude }>;

/**
 * Conversations and messages. PostgreSQL is the source of truth: a message is persisted (with a
 * per-conversation, gap-free `seq` assigned under a row lock) before anyone is told about it. Clients
 * resume after a disconnect with `GET /conversations/:id/messages?afterSeq=<last seen>`, so socket
 * delivery being best-effort never loses a message. Sends are idempotent on (sender, clientId).
 */
@Injectable()
export class MessagingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly relationships: RelationshipService,
    private readonly users: UserPresenter,
    private readonly media: MediaPresenter,
    private readonly notifications: NotificationWriter,
    private readonly realtime: RealtimePublisher,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  // ─── Conversations ─────────────────────────────────────────────────────────

  async createConversation(creatorId: string, participantIds: string[], title?: string): Promise<ConversationView> {
    const others = [...new Set(participantIds)].filter((id) => id !== creatorId);
    if (others.length === 0) throw AppError.badRequest('Add at least one other participant');
    if (others.length + 1 > MAX_GROUP_SIZE) throw AppError.badRequest(`Groups are limited to ${MAX_GROUP_SIZE} people`);
    const kind: ConversationKind = others.length === 1 ? 'DIRECT' : 'GROUP';

    const id = await this.prisma.$transaction(async (tx) => {
      const requests = new Map<string, boolean>();
      for (const other of others) requests.set(other, await this.messagePermission(tx, creatorId, other));

      if (kind === 'DIRECT') {
        const directKey = [creatorId, others[0]].sort().join(':');
        const existing = await tx.conversation.findUnique({ where: { directKey }, select: { id: true } });
        if (existing) {
          // Re-opening a conversation the creator had left/cleared is fine; membership is restored.
          await tx.conversationParticipant.updateMany({ where: { conversationId: existing.id, userId: creatorId }, data: { leftAt: null, archivedAt: null } });
          return existing.id;
        }
        try {
          const c = await tx.conversation.create({
            data: {
              kind, directKey, createdById: creatorId,
              participants: { create: [{ userId: creatorId }, { userId: others[0], isRequest: requests.get(others[0]) ?? false }] },
            },
            select: { id: true },
          });
          return c.id;
        } catch (error) {
          if (isUniqueViolation(error, 'direct_key')) return (await tx.conversation.findUniqueOrThrow({ where: { directKey }, select: { id: true } })).id;
          throw error;
        }
      }
      const c = await tx.conversation.create({
        data: {
          kind, title: title?.trim() || null, createdById: creatorId,
          participants: {
            create: [{ userId: creatorId, role: 'ADMIN' }, ...others.map((userId) => ({ userId, isRequest: requests.get(userId) ?? false }))],
          },
        },
        select: { id: true },
      });
      return c.id;
    });
    const view = await this.conversation(creatorId, id);
    await this.realtime.toUsers(others, 'conversation:updated', { conversationId: id });
    return view;
  }

  async listConversations(userId: string, cursor: string | undefined, limit: number, requests = false): Promise<Page<ConversationView>> {
    const c = cursor ? decodeCursor<{ t: string; id: string }>(cursor, ['t', 'id']) : undefined;
    const rows = await this.prisma.$queryRaw<Array<{ id: string; sort_at: Date }>>`
      SELECT c.id, COALESCE(c.last_message_at, c.created_at) AS sort_at
      FROM conversation_participants cp JOIN conversations c ON c.id = cp.conversation_id
      WHERE cp.user_id = ${userId}::uuid AND cp.left_at IS NULL AND cp.is_request = ${requests}
        AND (c.last_seq > cp.cleared_seq OR c.created_by_id = ${userId}::uuid)
        ${c ? Prisma.sql`AND (COALESCE(c.last_message_at, c.created_at), c.id) < (${new Date(c.t)}, ${c.id}::uuid)` : Prisma.empty}
      ORDER BY sort_at DESC, c.id DESC LIMIT ${limit + 1}`;
    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const views = await this.conversations(userId, page.map((r) => r.id));
    const last = page.at(-1);
    return { items: views, nextCursor: hasMore && last ? encodeCursor({ t: last.sort_at.toISOString(), id: last.id }) : null };
  }

  async conversation(userId: string, conversationId: string): Promise<ConversationView> {
    const [view] = await this.conversations(userId, [conversationId]);
    if (!view) throw AppError.notFound('Conversation');
    return view;
  }

  async updateConversation(userId: string, conversationId: string, changes: { title?: string; mutedUntil?: string | null; archived?: boolean }): Promise<ConversationView> {
    const p = await this.participant(this.prisma, conversationId, userId);
    await this.prisma.$transaction(async (tx) => {
      if (changes.title !== undefined) {
        if (p.conversation.kind !== 'GROUP') throw AppError.badRequest('Only groups have a title');
        if (p.role !== 'ADMIN') throw AppError.forbidden('Only group admins can rename the group');
        await tx.conversation.update({ where: { id: conversationId }, data: { title: changes.title.trim() || null } });
      }
      const data: Prisma.ConversationParticipantUpdateInput = {};
      if (changes.mutedUntil !== undefined) data.mutedUntil = changes.mutedUntil ? new Date(changes.mutedUntil) : null;
      if (changes.archived !== undefined) data.archivedAt = changes.archived ? new Date() : null;
      if (Object.keys(data).length) await tx.conversationParticipant.update({ where: { conversationId_userId: { conversationId, userId } }, data });
    });
    if (changes.title !== undefined) await this.realtime.toUsers(await this.memberIds(conversationId), 'conversation:updated', { conversationId });
    return this.conversation(userId, conversationId);
  }

  async acceptRequest(userId: string, conversationId: string): Promise<ConversationView> {
    await this.participant(this.prisma, conversationId, userId);
    await this.prisma.conversationParticipant.update({ where: { conversationId_userId: { conversationId, userId } }, data: { isRequest: false } });
    return this.conversation(userId, conversationId);
  }

  /** Group: leave. Direct: delete the history for me only (the other side keeps theirs). */
  async leave(userId: string, conversationId: string): Promise<void> {
    const p = await this.participant(this.prisma, conversationId, userId);
    if (p.conversation.kind === 'GROUP') {
      await this.prisma.conversationParticipant.update({ where: { conversationId_userId: { conversationId, userId } }, data: { leftAt: new Date() } });
      await this.realtime.toUsers(await this.memberIds(conversationId), 'conversation:updated', { conversationId });
    } else {
      await this.prisma.conversationParticipant.update({
        where: { conversationId_userId: { conversationId, userId } },
        data: { clearedSeq: p.conversation.lastSeq, lastReadSeq: p.conversation.lastSeq },
      });
    }
  }

  async addParticipants(userId: string, conversationId: string, userIds: string[]): Promise<ConversationView> {
    const p = await this.participant(this.prisma, conversationId, userId);
    if (p.conversation.kind !== 'GROUP') throw AppError.badRequest('Only groups can have members added');
    if (p.role !== 'ADMIN') throw AppError.forbidden('Only group admins can add members');
    await this.prisma.$transaction(async (tx) => {
      const current = await tx.conversationParticipant.count({ where: { conversationId, leftAt: null } });
      const fresh = [...new Set(userIds)].filter((id) => id !== userId);
      if (current + fresh.length > MAX_GROUP_SIZE) throw AppError.badRequest(`Groups are limited to ${MAX_GROUP_SIZE} people`);
      for (const other of fresh) {
        const isRequest = await this.messagePermission(tx, userId, other);
        await tx.conversationParticipant.upsert({
          where: { conversationId_userId: { conversationId, userId: other } },
          create: { conversationId, userId: other, isRequest, lastReadSeq: p.conversation.lastSeq, clearedSeq: p.conversation.lastSeq },
          update: { leftAt: null, isRequest, clearedSeq: p.conversation.lastSeq, lastReadSeq: p.conversation.lastSeq },
        });
      }
    });
    await this.realtime.toUsers(await this.memberIds(conversationId), 'conversation:updated', { conversationId });
    return this.conversation(userId, conversationId);
  }

  async removeParticipant(userId: string, conversationId: string, targetId: string): Promise<void> {
    const p = await this.participant(this.prisma, conversationId, userId);
    if (p.conversation.kind !== 'GROUP') throw AppError.badRequest('Not a group');
    if (p.role !== 'ADMIN' && targetId !== userId) throw AppError.forbidden('Only group admins can remove members');
    const members = await this.memberIds(conversationId);
    await this.prisma.conversationParticipant.updateMany({ where: { conversationId, userId: targetId, leftAt: null }, data: { leftAt: new Date() } });
    await this.realtime.toUsers(members, 'conversation:updated', { conversationId });
  }

  // ─── Messages ──────────────────────────────────────────────────────────────

  async send(senderId: string, conversationId: string, input: SendMessageInput): Promise<MessageView> {
    const text = input.text?.trim() || null;
    const mediaIds = input.mediaIds ?? [];
    if (!text && mediaIds.length === 0) throw AppError.badRequest('A message needs text or media');
    if (text && text.length > MAX_MESSAGE_LENGTH) throw AppError.badRequest(`Messages are limited to ${MAX_MESSAGE_LENGTH} characters`);

    const existing = await this.prisma.message.findUnique({ where: { senderId_clientId: { senderId, clientId: input.clientId } }, include: messageInclude });
    if (existing) {
      if (existing.conversationId !== conversationId) throw AppError.conflict('clientId already used');
      return (await this.present(senderId, [existing]))[0]; // resend after a lost ack: same message
    }
    await this.rateLimit(senderId);

    let result: { message: MessageRow; recipients: string[]; notify: string[] };
    try {
      result = await this.prisma.$transaction(async (tx) => {
        const me = await this.participant(tx, conversationId, senderId);
        const others = await tx.conversationParticipant.findMany({ where: { conversationId, leftAt: null, userId: { not: senderId } }, select: { userId: true, mutedUntil: true, isRequest: true } });
        if (me.conversation.kind === 'DIRECT') {
          const other = others[0] ?? (await tx.conversationParticipant.findFirst({ where: { conversationId, userId: { not: senderId } }, select: { userId: true, mutedUntil: true, isRequest: true } }));
          if (!other || (await this.relationships.isBlockedEitherWay(senderId, other.userId, tx))) {
            throw new AppError('BLOCKED', 'You can’t message this account', HttpStatus.FORBIDDEN);
          }
          // A direct conversation the other side deleted re-appears for them on a new message.
          await tx.conversationParticipant.updateMany({ where: { conversationId, userId: other.userId }, data: { leftAt: null } });
          if (!others.length) others.push(other);
        }
        if (input.replyToId) {
          const target = await tx.message.findFirst({ where: { id: input.replyToId, conversationId }, select: { seq: true } });
          if (!target || target.seq <= me.clearedSeq) throw AppError.notFound('Message');
        }

        const [{ last_seq: seq }] = await tx.$queryRaw<Array<{ last_seq: number }>>`
          UPDATE conversations SET last_seq = last_seq + 1, last_message_at = now(), updated_at = now()
          WHERE id = ${conversationId}::uuid RETURNING last_seq`;
        const type: MessageType = mediaIds.length ? await this.mediaType(tx, senderId, mediaIds) : 'TEXT';
        const message = await tx.message.create({
          data: { conversationId, senderId, clientId: input.clientId, seq, type, text, replyToId: input.replyToId },
        });
        if (mediaIds.length) await tx.messageAttachment.createMany({ data: mediaIds.map((mediaId, position) => ({ messageId: message.id, mediaId, position })) });
        await tx.conversation.update({ where: { id: conversationId }, data: { lastMessageId: message.id } });
        await tx.conversationParticipant.update({
          where: { conversationId_userId: { conversationId, userId: senderId } },
          data: { lastReadSeq: seq, lastDeliveredSeq: seq, lastReadAt: new Date(), archivedAt: null, isRequest: false },
        });
        await tx.conversationParticipant.updateMany({ where: { conversationId, userId: { in: others.map((o) => o.userId) } }, data: { archivedAt: null } });

        const now = new Date();
        const notify = await this.notifications.write(tx, others
          .filter((o) => !o.mutedUntil || o.mutedUntil < now)
          .map((o) => o.isRequest
            // Not connected: one "message request" notification per conversation, not one per message.
            ? { recipientId: o.userId, actorId: senderId, type: 'MESSAGE_REQUEST' as const, conversationId, dedupeKey: `MESSAGE_REQUEST:${conversationId}` }
            : { recipientId: o.userId, actorId: senderId, type: 'MESSAGE' as const, conversationId, dedupeKey: `MESSAGE:${message.id}`, data: { messageId: message.id, messageType: type } }));
        const full = await tx.message.findUniqueOrThrow({ where: { id: message.id }, include: messageInclude });
        return { message: full, recipients: others.map((o) => o.userId), notify };
      });
    } catch (error) {
      if (isUniqueViolation(error, 'client_id')) {
        const winner = await this.prisma.message.findUniqueOrThrow({ where: { senderId_clientId: { senderId, clientId: input.clientId } }, include: messageInclude });
        return (await this.present(senderId, [winner]))[0];
      }
      throw error;
    }

    const [view] = await this.present(senderId, [result.message]);
    await this.realtime.toUsers([senderId, ...result.recipients], 'message:new', view);
    await this.notifications.dispatch(result.notify, true);
    return view;
  }

  /** Seq-based paging: `beforeSeq` for history (newest first), `afterSeq` for catching up after a reconnect (oldest first). */
  async messages(userId: string, conversationId: string, opts: { beforeSeq?: number; afterSeq?: number; limit: number }): Promise<{ items: MessageView[]; hasMore: boolean }> {
    const p = await this.participant(this.prisma, conversationId, userId);
    const floor = p.clearedSeq;
    const ascending = opts.afterSeq !== undefined;
    const rows = await this.prisma.message.findMany({
      where: {
        conversationId,
        seq: ascending
          ? { gt: Math.max(opts.afterSeq ?? 0, floor) }
          : { gt: floor, ...(opts.beforeSeq !== undefined ? { lt: opts.beforeSeq } : {}) },
      },
      orderBy: { seq: ascending ? 'asc' : 'desc' },
      take: opts.limit + 1,
      include: messageInclude,
    });
    const hasMore = rows.length > opts.limit;
    return { items: await this.present(userId, hasMore ? rows.slice(0, opts.limit) : rows), hasMore };
  }

  async edit(userId: string, messageId: string, text: string): Promise<MessageView> {
    const body = text.trim();
    if (!body || body.length > MAX_MESSAGE_LENGTH) throw AppError.badRequest('Invalid message text');
    const message = await this.prisma.message.findFirst({ where: { id: messageId, senderId: userId, deletedAt: null } });
    if (!message) throw AppError.notFound('Message');
    await this.participant(this.prisma, message.conversationId, userId);
    if (Date.now() - message.createdAt.getTime() > EDIT_WINDOW_MS) throw AppError.badRequest('Messages can only be edited for 15 minutes');
    if (message.type !== 'TEXT' && !message.text) throw AppError.badRequest('This message has no text to edit');
    const updated = await this.prisma.message.update({ where: { id: messageId }, data: { text: body, editedAt: new Date() }, include: messageInclude });
    const [view] = await this.present(userId, [updated]);
    await this.realtime.toUsers(await this.memberIds(message.conversationId), 'message:updated', view);
    return view;
  }

  /** Delete for everyone (sender only). The row stays as a tombstone so seq stays gap-free. */
  async remove(userId: string, messageId: string): Promise<void> {
    const message = await this.prisma.message.findFirst({ where: { id: messageId, senderId: userId, deletedAt: null } });
    if (!message) throw AppError.notFound('Message');
    await this.prisma.$transaction(async (tx) => {
      await tx.message.update({ where: { id: messageId }, data: { deletedAt: new Date(), text: null } });
      await tx.messageReaction.deleteMany({ where: { messageId } });
      await tx.mediaAsset.updateMany({ where: { attachment: { messageId } }, data: { deletedAt: new Date() } });
      await tx.notification.deleteMany({ where: { dedupeKey: `MESSAGE:${messageId}` } });
    });
    await this.realtime.toUsers(await this.memberIds(message.conversationId), 'message:deleted', { conversationId: message.conversationId, messageId, seq: message.seq });
  }

  async react(userId: string, messageId: string, emoji: string, add: boolean): Promise<MessageView> {
    const message = await this.prisma.message.findFirst({ where: { id: messageId, deletedAt: null } });
    if (!message) throw AppError.notFound('Message');
    const p = await this.participant(this.prisma, message.conversationId, userId);
    if (message.seq <= p.clearedSeq) throw AppError.notFound('Message');
    if (add) {
      await this.prisma.$executeRaw`INSERT INTO message_reactions (message_id, user_id, emoji, created_at) VALUES (${messageId}::uuid, ${userId}::uuid, ${emoji}, now()) ON CONFLICT DO NOTHING`;
    } else {
      await this.prisma.messageReaction.deleteMany({ where: { messageId, userId, emoji } });
    }
    const row = await this.prisma.message.findUniqueOrThrow({ where: { id: messageId }, include: messageInclude });
    const [view] = await this.present(userId, [row]);
    await this.realtime.toUsers(await this.memberIds(message.conversationId), 'message:reaction', { conversationId: message.conversationId, messageId, reactions: row.reactions.map((r) => ({ emoji: r.emoji, userId: r.userId })) });
    return view;
  }

  /** Read/delivered watermarks only move forward and never past the latest message. */
  async markRead(userId: string, conversationId: string, seq: number): Promise<{ lastReadSeq: number }> {
    return { lastReadSeq: await this.advance(userId, conversationId, seq, 'read') };
  }

  async markDelivered(userId: string, conversationId: string, seq: number): Promise<{ lastDeliveredSeq: number }> {
    return { lastDeliveredSeq: await this.advance(userId, conversationId, seq, 'delivered') };
  }

  /** Returns the new watermark. */
  private async advance(userId: string, conversationId: string, seq: number, kind: 'read' | 'delivered'): Promise<number> {
    await this.participant(this.prisma, conversationId, userId);
    const rows = kind === 'read'
      ? await this.prisma.$queryRaw<Array<{ v: number }>>`
          UPDATE conversation_participants cp
          SET last_read_seq = GREATEST(cp.last_read_seq, LEAST(${seq}, c.last_seq)),
              last_delivered_seq = GREATEST(cp.last_delivered_seq, LEAST(${seq}, c.last_seq)),
              last_read_at = now()
          FROM conversations c
          WHERE c.id = cp.conversation_id AND cp.conversation_id = ${conversationId}::uuid AND cp.user_id = ${userId}::uuid
          RETURNING cp.last_read_seq AS v`
      : await this.prisma.$queryRaw<Array<{ v: number }>>`
          UPDATE conversation_participants cp
          SET last_delivered_seq = GREATEST(cp.last_delivered_seq, LEAST(${seq}, c.last_seq))
          FROM conversations c
          WHERE c.id = cp.conversation_id AND cp.conversation_id = ${conversationId}::uuid AND cp.user_id = ${userId}::uuid
          RETURNING cp.last_delivered_seq AS v`;
    const value = rows[0]?.v ?? 0;
    const settings = await this.prisma.userSettings.findUnique({ where: { userId }, select: { sendReadReceipts: true } });
    if (kind === 'delivered' || settings?.sendReadReceipts !== false) {
      const others = (await this.memberIds(conversationId)).filter((id) => id !== userId);
      await this.realtime.toUsers(others, kind === 'read' ? 'conversation:read' : 'conversation:delivered', { conversationId, userId, seq: value });
    }
    if (kind === 'read') {
      await this.realtime.toUsers([userId], 'conversation:read', { conversationId, userId, seq: value }); // sync my other devices
      // Message notifications up to here are read too.
      await this.prisma.notification.updateMany({ where: { recipientId: userId, conversationId, type: 'MESSAGE', readAt: null }, data: { readAt: new Date() } });
    }
    return value;
  }

  /** Typing indicators are ephemeral: validated, relayed, never stored. */
  async typing(userId: string, conversationId: string, isTyping: boolean): Promise<void> {
    await this.participant(this.prisma, conversationId, userId);
    const others = (await this.memberIds(conversationId)).filter((id) => id !== userId);
    await this.realtime.toUsers(others, 'typing', { conversationId, userId, isTyping });
  }

  /** Total unread across conversations (excludes requests), for the app badge. */
  async unreadTotal(userId: string): Promise<number> {
    const [row] = await this.prisma.$queryRaw<Array<{ n: number }>>`
      SELECT count(*)::int AS n FROM conversation_participants cp
      JOIN messages m ON m.conversation_id = cp.conversation_id AND m.seq > GREATEST(cp.last_read_seq, cp.cleared_seq)
      WHERE cp.user_id = ${userId}::uuid AND cp.left_at IS NULL AND NOT cp.is_request
        AND m.sender_id <> ${userId}::uuid AND m.deleted_at IS NULL`;
    return row?.n ?? 0;
  }

  async memberIds(conversationId: string): Promise<string[]> {
    const rows = await this.prisma.conversationParticipant.findMany({ where: { conversationId, leftAt: null }, select: { userId: true } });
    return rows.map((r) => r.userId);
  }

  /** Throws 404 unless the user is a current participant — the single membership gate. */
  async participant(db: Tx | PrismaService, conversationId: string, userId: string) {
    const p = await db.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
      include: { conversation: { select: { kind: true, lastSeq: true } } },
    });
    if (!p || p.leftAt) throw AppError.notFound('Conversation');
    return p;
  }

  // ─── Internals ─────────────────────────────────────────────────────────────

  /**
   * Can `senderId` start messaging `recipientId`? Throws when not allowed. Returns true when the
   * conversation should land in the recipient's message requests (no connection between them).
   */
  private async messagePermission(tx: Tx, senderId: string, recipientId: string): Promise<boolean> {
    const recipient = await tx.user.findUnique({ where: { id: recipientId }, select: { status: true, settings: { select: { allowMessagesFrom: true } } } });
    if (!recipient || recipient.status !== 'ACTIVE') throw AppError.notFound('User');
    const rel = await this.relationships.between(recipientId, senderId, tx); // from the recipient's point of view
    if (rel.blocking || rel.blockedBy) throw AppError.notFound('User');
    const connected = rel.isContact || rel.following;
    const permission = recipient.settings?.allowMessagesFrom ?? 'EVERYONE';
    if (permission === 'NOBODY' || (permission === 'CONNECTIONS' && !connected)) {
      throw new AppError('FORBIDDEN', 'This account does not accept messages from you', HttpStatus.FORBIDDEN);
    }
    return !connected;
  }

  private async mediaType(tx: Tx, ownerId: string, mediaIds: string[]): Promise<MessageType> {
    if (new Set(mediaIds).size !== mediaIds.length || mediaIds.length > 10) throw AppError.badRequest('Invalid media list');
    const assets = await tx.mediaAsset.findMany({
      where: { id: { in: mediaIds }, ownerId, purpose: 'MESSAGE', deletedAt: null, status: { in: ['PROCESSING', 'READY'] }, attachment: null },
      select: { kind: true },
    });
    if (assets.length !== mediaIds.length) throw AppError.badRequest('One or more media items are missing, not uploaded, or already used');
    return assets.some((a) => a.kind === 'VIDEO') ? 'VIDEO' : 'IMAGE';
  }

  private async rateLimit(userId: string) {
    const key = `rl:msg:${userId}:${Math.floor(Date.now() / (SEND_LIMIT.windowSeconds * 1000))}`;
    const [[, n]] = (await this.redis.multi().incr(key).expire(key, SEND_LIMIT.windowSeconds * 2).exec()) as [[null, number]];
    if (n > SEND_LIMIT.count) throw new AppError('RATE_LIMITED', 'You are sending messages too quickly', HttpStatus.TOO_MANY_REQUESTS);
  }

  private async conversations(userId: string, ids: string[]): Promise<ConversationView[]> {
    if (ids.length === 0) return [];
    const convs = await this.prisma.conversation.findMany({
      where: { id: { in: ids }, participants: { some: { userId, leftAt: null } } },
      include: {
        participants: { where: { leftAt: null }, include: { user: { select: { settings: { select: { sendReadReceipts: true } } } } } },
        lastMessage: { include: messageInclude },
      },
    });
    const unread = await this.prisma.$queryRaw<Array<{ conversation_id: string; n: number }>>`
      SELECT cp.conversation_id, count(m.id)::int AS n FROM conversation_participants cp
      JOIN messages m ON m.conversation_id = cp.conversation_id AND m.seq > GREATEST(cp.last_read_seq, cp.cleared_seq)
        AND m.sender_id <> ${userId}::uuid AND m.deleted_at IS NULL
      WHERE cp.user_id = ${userId}::uuid AND cp.conversation_id = ANY(${ids}::uuid[])
      GROUP BY cp.conversation_id`;
    const unreadBy = new Map(unread.map((u) => [u.conversation_id, u.n]));
    const participantIds = convs.flatMap((c) => c.participants.map((p) => p.userId));
    const summaries = await this.users.summaries(participantIds);
    const knownPhones = new Map((await this.prisma.contactLink.findMany({
      where: { ownerId: userId, contactId: { in: participantIds } },
      select: { contact: { select: { id: true, phoneNumber: true } } },
    })).map((c) => [c.contact.id, c.contact.phoneNumber]));
    const me = await this.prisma.user.findUnique({ where: { id: userId }, select: { phoneNumber: true } });
    if (me) knownPhones.set(userId, me.phoneNumber);
    const lastMessages = await this.present(userId, convs.flatMap((c) => (c.lastMessage ? [c.lastMessage] : [])));
    const lastBy = new Map(lastMessages.map((m) => [m.conversationId, m]));
    const byId = new Map(convs.map((c) => [c.id, c]));

    return ids.flatMap((id) => {
      const c = byId.get(id);
      if (!c) return [];
      const mine = c.participants.find((p) => p.userId === userId)!;
      const last = lastBy.get(c.id);
      return [{
        id: c.id,
        kind: c.kind,
        title: c.title,
        participants: c.participants.flatMap((p) => {
          const s = summaries.get(p.userId);
          if (!s) return [];
          const shareReceipts = p.userId === userId || p.user.settings?.sendReadReceipts !== false;
          return [{ ...s, role: p.role, lastReadSeq: shareReceipts ? p.lastReadSeq : null, lastDeliveredSeq: p.lastDeliveredSeq, phoneNumber: knownPhones.get(p.userId) ?? null }];
        }),
        lastMessage: last && last.seq > mine.clearedSeq ? last : null,
        lastSeq: c.lastSeq,
        unreadCount: unreadBy.get(c.id) ?? 0,
        isRequest: mine.isRequest,
        mutedUntil: mine.mutedUntil?.toISOString() ?? null,
        archived: !!mine.archivedAt,
        lastMessageAt: c.lastMessageAt?.toISOString() ?? null,
        createdAt: c.createdAt.toISOString(),
      }];
    });
  }

  async present(viewerId: string, rows: MessageRow[]): Promise<MessageView[]> {
    const senders = await this.users.summaries(rows.map((r) => r.senderId));
    return Promise.all(rows.map(async (m) => {
      const deleted = !!m.deletedAt;
      const grouped = new Map<string, { count: number; mine: boolean }>();
      for (const r of m.reactions) {
        const g = grouped.get(r.emoji) ?? { count: 0, mine: false };
        g.count += 1;
        g.mine ||= r.userId === viewerId;
        grouped.set(r.emoji, g);
      }
      return {
        id: m.id,
        clientId: m.clientId,
        conversationId: m.conversationId,
        seq: m.seq,
        sender: senders.get(m.senderId) ?? null,
        senderId: m.senderId,
        type: m.type,
        text: deleted ? null : m.text,
        media: deleted ? [] : await Promise.all(m.attachments.map((a) => this.media.present(a.media, 'private'))),
        replyTo: m.replyTo
          ? { id: m.replyTo.id, senderId: m.replyTo.senderId, text: m.replyTo.deletedAt ? null : m.replyTo.text?.slice(0, 200) ?? null, type: m.replyTo.type, deleted: !!m.replyTo.deletedAt }
          : null,
        reactions: [...grouped.entries()].map(([emoji, g]) => ({ emoji, ...g })),
        editedAt: m.editedAt?.toISOString() ?? null,
        deleted,
        createdAt: m.createdAt.toISOString(),
      };
    }));
  }
}
