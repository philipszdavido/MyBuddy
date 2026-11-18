import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Notification } from '@prisma/client';
import { Job } from 'bullmq';
import { PrismaService } from '../prisma/prisma.service';
import { DeliverNotificationJob, Q } from '../queues/queues';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { UserPresenter } from '../users/user-presenter.service';
import { FcmSender, PushMessage } from './fcm.sender';
import { deepLinkFor, NotificationsService } from './notifications.service';

/**
 * Delivers one notification: real-time event to the recipient's open sockets, then FCM push to every
 * registered device unless push is disabled for that type. Per-device delivery rows make retries
 * idempotent (a device already SENT is skipped), invalid tokens are deleted, and the notification is
 * marked processed so the outbox sweeper leaves it alone.
 */
@Processor(Q.notifications, { concurrency: Number(process.env.WORKER_CONCURRENCY ?? 5) * 2 })
export class NotificationProcessor extends WorkerHost {
  private readonly logger = new Logger(NotificationProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcm: FcmSender,
    private readonly users: UserPresenter,
    private readonly inbox: NotificationsService,
    private readonly realtime: RealtimePublisher,
  ) {
    super();
  }

  async process(job: Job<DeliverNotificationJob>): Promise<{ sent: number; skipped?: string }> {
    const n = await this.prisma.notification.findUnique({ where: { id: job.data.notificationId } });
    if (!n || n.pushProcessedAt) return { sent: 0, skipped: 'gone-or-processed' };
    const actor = n.actorId ? await this.users.summary(n.actorId) : null;

    if (job.attemptsMade === 0) {
      await this.realtime.toUsers([n.recipientId], 'notification:new', this.inbox.view(n, actor));
    }

    const pref = await this.prisma.notificationPreference.findUnique({ where: { userId_type: { userId: n.recipientId, type: n.type } } });
    const devices = pref?.push === false
      ? []
      : await this.prisma.userDevice.findMany({
          where: { userId: n.recipientId, deliveries: { none: { notificationId: n.id, status: 'SENT' } } },
          select: { id: true, fcmToken: true },
        });
    if (devices.length === 0) {
      await this.finish(n.id);
      return { sent: 0, skipped: pref?.push === false ? 'disabled' : 'no-devices' };
    }

    const message = await this.render(n, actor?.displayName ?? 'Someone');
    const results = await this.fcm.send(devices.map((d) => d.fcmToken), message);
    let sent = 0;
    let retryable = 0;
    for (const [i, r] of results.entries()) {
      const device = devices[i];
      if (r.invalidToken) {
        await this.prisma.userDevice.deleteMany({ where: { id: device.id } });
        continue;
      }
      if (r.ok) sent += 1;
      else retryable += 1;
      await this.prisma.notificationDelivery.upsert({
        where: { notificationId_deviceId: { notificationId: n.id, deviceId: device.id } },
        create: { notificationId: n.id, deviceId: device.id, status: r.ok ? 'SENT' : 'FAILED', error: r.error, attemptedAt: new Date() },
        update: { status: r.ok ? 'SENT' : 'FAILED', error: r.error ?? null, attemptedAt: new Date() },
      });
    }
    if (retryable > 0 && job.attemptsMade + 1 < (job.opts.attempts ?? 1)) {
      throw new Error(`${retryable} push deliveries failed; retrying`);
    }
    await this.finish(n.id);
    return { sent };
  }

  private finish(id: string) {
    return this.prisma.notification.update({ where: { id }, data: { pushProcessedAt: new Date() } });
  }

  /** Lock-screen text never contains message or comment content (privacy). */
  private async render(n: Notification, actor: string): Promise<PushMessage> {
    const deepLink = deepLinkFor(n);
    const data: Record<string, string> = { deepLink, type: n.type, notificationId: n.id };
    if (n.postId) data.postId = n.postId;
    if (n.conversationId) data.chatId = n.conversationId; // key read by the iOS DeepLink(userInfo:) parser
    const meta = (n.data ?? {}) as Record<string, unknown>;
    const badge = await this.badge(n.recipientId);
    const base = { data, badge, collapseKey: n.dedupeKey.slice(0, 64) };
    switch (n.type) {
      case 'MESSAGE':
        return { ...base, title: actor, body: meta.messageType === 'IMAGE' ? 'Sent you a photo' : meta.messageType === 'VIDEO' ? 'Sent you a video' : 'Sent you a message', threadId: n.conversationId ?? undefined, collapseKey: undefined };
      case 'MESSAGE_REQUEST':
        return { ...base, title: actor, body: 'Wants to send you a message' };
      case 'FOLLOW':
        return { ...base, title: 'New follower', body: `${actor} started following you` };
      case 'FOLLOW_REQUEST':
        return { ...base, title: 'Follow request', body: `${actor} wants to follow you` };
      case 'FOLLOW_ACCEPTED':
        return { ...base, title: 'Request accepted', body: `${actor} accepted your follow request` };
      case 'POST_REACTION':
        return { ...base, title: actor, body: 'Liked your post' };
      case 'COMMENT_REACTION':
        return { ...base, title: actor, body: 'Liked your comment' };
      case 'COMMENT':
        return { ...base, title: actor, body: 'Commented on your post' };
      case 'COMMENT_REPLY':
        return { ...base, title: actor, body: 'Replied to your comment' };
      case 'MENTION':
        return { ...base, title: actor, body: 'Mentioned you' };
      case 'REPOST':
        return { ...base, title: actor, body: 'Reposted your post' };
    }
  }

  private async badge(userId: string): Promise<number> {
    const [row] = await this.prisma.$queryRaw<Array<{ n: number }>>`
      SELECT (
        (SELECT count(*) FROM notifications WHERE recipient_id = ${userId}::uuid AND read_at IS NULL AND type <> 'MESSAGE')
        + (SELECT count(*) FROM conversation_participants cp
             JOIN messages m ON m.conversation_id = cp.conversation_id AND m.seq > GREATEST(cp.last_read_seq, cp.cleared_seq)
            WHERE cp.user_id = ${userId}::uuid AND cp.left_at IS NULL AND NOT cp.is_request
              AND m.sender_id <> ${userId}::uuid AND m.deleted_at IS NULL)
      )::int AS n`;
    return Math.min(row?.n ?? 0, 999);
  }
}

/** Re-dispatches notifications whose delivery job never ran (crash between commit and enqueue). */
export async function sweepUndispatched(prisma: PrismaService, enqueue: (ids: string[]) => Promise<void>, olderThanMs = 60_000): Promise<number> {
  const stale = await prisma.notification.findMany({
    where: { pushProcessedAt: null, createdAt: { lt: new Date(Date.now() - olderThanMs), gt: new Date(Date.now() - 24 * 3600_000) } },
    select: { id: true },
    take: 1000,
  });
  if (stale.length) await enqueue(stale.map((s) => s.id));
  return stale.length;
}
