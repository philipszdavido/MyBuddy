import { InjectQueue } from '@nestjs/bullmq';
import { Global, Injectable, Module } from '@nestjs/common';
import { NotificationType, Prisma } from '@prisma/client';
import { Queue } from 'bullmq';
import { Tx } from '../prisma/prisma.service';
import { DeliverNotificationJob, PRIORITY, Q } from '../queues/queues';

export interface NewNotification {
  recipientId: string;
  actorId: string;
  type: NotificationType;
  /** Same key => same notification (re-liking a post does not notify twice). */
  dedupeKey: string;
  postId?: string;
  commentId?: string;
  conversationId?: string;
  data?: Prisma.InputJsonValue;
}

/**
 * Transactional outbox for notifications. `write` runs inside the caller's transaction, so the
 * in-app notification exists if and only if the action committed. `dispatch` enqueues push delivery
 * after commit; if the process dies in between, the cleanup queue's sweeper re-dispatches rows that
 * have no delivery records. FCM is never called inside a transaction.
 */
@Injectable()
export class NotificationWriter {
  constructor(@InjectQueue(Q.notifications) private readonly queue: Queue<DeliverNotificationJob>) {}

  /** Returns ids of newly created notifications (skips self, blocked, muted, disabled, duplicates). */
  async write(tx: Tx, items: NewNotification[]): Promise<string[]> {
    const ids: string[] = [];
    for (const n of items) {
      if (n.recipientId === n.actorId) continue;
      const [suppressed] = await tx.$queryRaw<Array<{ skip: boolean }>>`
        SELECT (
          EXISTS(SELECT 1 FROM user_blocks WHERE (blocker_id = ${n.recipientId}::uuid AND blocked_id = ${n.actorId}::uuid)
                                              OR (blocker_id = ${n.actorId}::uuid AND blocked_id = ${n.recipientId}::uuid))
          OR EXISTS(SELECT 1 FROM user_mutes WHERE muter_id = ${n.recipientId}::uuid AND muted_id = ${n.actorId}::uuid)
          OR EXISTS(SELECT 1 FROM notification_preferences WHERE user_id = ${n.recipientId}::uuid
                      AND type = ${n.type}::"NotificationType" AND in_app = false AND push = false)
          OR NOT EXISTS(SELECT 1 FROM users WHERE id = ${n.recipientId}::uuid AND status = 'ACTIVE')
        ) AS skip`;
      if (suppressed?.skip) continue;
      const rows = await tx.$queryRaw<Array<{ id: string }>>`
        INSERT INTO notifications (id, recipient_id, actor_id, type, post_id, comment_id, conversation_id, dedupe_key, data, created_at)
        VALUES (gen_random_uuid(), ${n.recipientId}::uuid, ${n.actorId}::uuid, ${n.type}::"NotificationType",
                ${n.postId ?? null}::uuid, ${n.commentId ?? null}::uuid, ${n.conversationId ?? null}::uuid,
                ${n.dedupeKey}, ${n.data === undefined ? null : JSON.stringify(n.data)}::jsonb, now())
        ON CONFLICT (recipient_id, dedupe_key) DO NOTHING
        RETURNING id`;
      if (rows[0]) ids.push(rows[0].id);
    }
    return ids;
  }

  /** Call after the transaction committed. Job id = notification id, so double dispatch is harmless. */
  async dispatch(ids: string[], realtime = false): Promise<void> {
    if (ids.length === 0) return;
    await this.queue.addBulk(
      ids.map((notificationId) => ({
        name: 'deliver',
        data: { notificationId },
        opts: { jobId: `n-${notificationId}`, priority: realtime ? PRIORITY.realtime : PRIORITY.normal },
      })),
    );
  }

  /** Removes notifications whose cause was undone (unlike, unfollow), so the inbox stays truthful. */
  async retract(tx: Tx, recipientId: string, dedupeKey: string): Promise<void> {
    await tx.notification.deleteMany({ where: { recipientId, dedupeKey, readAt: null } });
  }
}

@Global()
@Module({ providers: [NotificationWriter], exports: [NotificationWriter] })
export class NotificationsCoreModule {}
