import { Injectable } from '@nestjs/common';
import { Notification, NotificationType, Prisma } from '@prisma/client';
import { AppError } from '../common/errors/app-error';
import { DEFAULT_PAGE, Page, parseTimeCursor, timeCursor, toPage } from '../common/pagination/cursor';
import { PrismaService } from '../prisma/prisma.service';
import { UserPresenter, UserSummary } from '../users/user-presenter.service';

export interface NotificationView {
  id: string;
  type: NotificationType;
  actor: UserSummary | null;
  postId: string | null;
  commentId: string | null;
  conversationId: string | null;
  deepLink: string;
  read: boolean;
  data: Prisma.JsonValue | null;
  createdAt: string;
}

/** Chat messages have their own unread counts; the activity inbox does not list them. */
const INBOX_TYPES = Object.values(NotificationType).filter((t) => t !== 'MESSAGE');

/** Deep links understood by the iOS DeepLink parser: mybuddy://chat|profile|post/{id}. */
export function deepLinkFor(n: Pick<Notification, 'type' | 'postId' | 'conversationId' | 'actorId'>): string {
  if ((n.type === 'MESSAGE' || n.type === 'MESSAGE_REQUEST') && n.conversationId) return `mybuddy://chat/${n.conversationId}`;
  if (n.postId) return `mybuddy://post/${n.postId}`;
  if (n.actorId) return `mybuddy://profile/${n.actorId}`;
  return 'mybuddy://';
}

export interface DeviceInput {
  installationId: string;
  fcmToken: string;
  platform: string;
  appVersion?: string;
  locale?: string;
}

@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService, private readonly users: UserPresenter) {}

  /** Inbox types minus the ones the user hid from Activity (preference inApp = false). */
  private async visibleTypes(userId: string): Promise<NotificationType[]> {
    const hidden = await this.prisma.notificationPreference.findMany({ where: { userId, inApp: false }, select: { type: true } });
    const set = new Set(hidden.map((h) => h.type));
    return INBOX_TYPES.filter((t) => !set.has(t));
  }

  async list(userId: string, cursor?: string, limit = DEFAULT_PAGE, unreadOnly = false): Promise<Page<NotificationView>> {
    const c = parseTimeCursor(cursor);
    const rows = await this.prisma.notification.findMany({
      where: {
        recipientId: userId,
        type: { in: await this.visibleTypes(userId) },
        ...(unreadOnly ? { readAt: null } : {}),
        ...(c ? { OR: [{ createdAt: { lt: c.date } }, { createdAt: c.date, id: { lt: c.id } }] } : {}),
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const actors = await this.users.summaries(rows.flatMap((r) => (r.actorId ? [r.actorId] : [])));
    return toPage(rows, limit, (r) => this.view(r, r.actorId ? actors.get(r.actorId) ?? null : null), (r) => timeCursor(r.createdAt, r.id));
  }

  view(n: Notification, actor: UserSummary | null): NotificationView {
    return {
      id: n.id,
      type: n.type,
      actor,
      postId: n.postId,
      commentId: n.commentId,
      conversationId: n.conversationId,
      deepLink: deepLinkFor(n),
      read: !!n.readAt,
      data: n.data,
      createdAt: n.createdAt.toISOString(),
    };
  }

  async unreadCount(userId: string): Promise<number> {
    return this.prisma.notification.count({ where: { recipientId: userId, readAt: null, type: { in: await this.visibleTypes(userId) } } });
  }

  async markRead(userId: string, id: string): Promise<void> {
    const { count } = await this.prisma.notification.updateMany({ where: { id, recipientId: userId }, data: { readAt: new Date() } });
    if (count === 0) throw AppError.notFound('Notification');
  }

  async markAllRead(userId: string): Promise<{ updated: number }> {
    const { count } = await this.prisma.notification.updateMany({ where: { recipientId: userId, readAt: null, type: { in: INBOX_TYPES } }, data: { readAt: new Date() } });
    return { updated: count };
  }

  /** Every type with its current setting (defaults: push and in-app on). */
  async preferences(userId: string): Promise<Array<{ type: NotificationType; push: boolean; inApp: boolean }>> {
    const rows = await this.prisma.notificationPreference.findMany({ where: { userId } });
    const by = new Map(rows.map((r) => [r.type, r]));
    return Object.values(NotificationType).map((type) => ({ type, push: by.get(type)?.push ?? true, inApp: by.get(type)?.inApp ?? true }));
  }

  async setPreferences(userId: string, prefs: Array<{ type: NotificationType; push?: boolean; inApp?: boolean }>) {
    await this.prisma.$transaction(prefs.map((p) =>
      this.prisma.notificationPreference.upsert({
        where: { userId_type: { userId, type: p.type } },
        create: { userId, type: p.type, push: p.push ?? true, inApp: p.inApp ?? true },
        update: { push: p.push, inApp: p.inApp },
      })));
    return this.preferences(userId);
  }

  /**
   * Registers (or refreshes) this installation's FCM token. A token belongs to one installation:
   * if the device previously signed in as someone else, that registration is removed first, so a
   * shared phone never receives the previous account's notifications.
   */
  async registerDevice(userId: string, d: DeviceInput): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      await tx.userDevice.deleteMany({ where: { fcmToken: d.fcmToken, NOT: { userId, installationId: d.installationId } } });
      await tx.userDevice.upsert({
        where: { userId_installationId: { userId, installationId: d.installationId } },
        create: { userId, ...d, lastSeenAt: new Date() },
        update: { fcmToken: d.fcmToken, platform: d.platform, appVersion: d.appVersion, locale: d.locale, lastSeenAt: new Date() },
      });
    });
  }

  async unregisterDevice(userId: string, installationId: string): Promise<void> {
    await this.prisma.userDevice.deleteMany({ where: { userId, installationId } });
  }
}
