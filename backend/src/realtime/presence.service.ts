import { Inject, Injectable } from '@nestjs/common';
import type Redis from 'ioredis';
import { PrismaService } from '../prisma/prisma.service';
import { REDIS } from '../redis/redis.module';
import { RealtimePublisher } from './realtime.publisher';

const TTL_SECONDS = 70; // clients heartbeat every 25s; a crashed instance's sockets expire on their own

export interface PresenceView {
  userId: string;
  online: boolean;
  lastSeenAt: string | null;
}

/**
 * Online/offline presence in Redis. Each socket holds a member in a per-user sorted set scored by its
 * expiry; a user is online while any member is unexpired, so multiple devices and instance crashes are
 * handled without counters drifting. "Last seen" is persisted on disconnect. Users who turned off
 * showActivityStatus appear offline with no last-seen time.
 */
@Injectable()
export class PresenceService {
  constructor(
    @Inject(REDIS) private readonly redis: Redis,
    private readonly prisma: PrismaService,
    private readonly publisher: RealtimePublisher,
  ) {}

  private key(userId: string) {
    return `presence:${userId}`;
  }

  async connect(userId: string, socketId: string): Promise<void> {
    const wasOnline = await this.isOnline(userId);
    await this.touch(userId, socketId);
    if (!wasOnline) await this.broadcast(userId);
  }

  async touch(userId: string, socketId: string): Promise<void> {
    const key = this.key(userId);
    await this.redis.multi().zadd(key, Date.now() + TTL_SECONDS * 1000, socketId).expire(key, TTL_SECONDS).exec();
  }

  async disconnect(userId: string, socketId: string): Promise<void> {
    await this.redis.zrem(this.key(userId), socketId);
    if (!(await this.isOnline(userId))) {
      await this.prisma.user.update({ where: { id: userId }, data: { lastActiveAt: new Date() } }).catch(() => undefined);
      await this.broadcast(userId);
    }
  }

  async isOnline(userId: string): Promise<boolean> {
    const key = this.key(userId);
    await this.redis.zremrangebyscore(key, 0, Date.now());
    return (await this.redis.zcard(key)) > 0;
  }

  async views(userIds: string[]): Promise<PresenceView[]> {
    const users = await this.prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, lastActiveAt: true, settings: { select: { showActivityStatus: true } } },
    });
    return Promise.all(
      users.map(async (u) => {
        const visible = u.settings?.showActivityStatus !== false;
        return {
          userId: u.id,
          online: visible && (await this.isOnline(u.id)),
          lastSeenAt: visible ? u.lastActiveAt?.toISOString() ?? null : null,
        };
      }),
    );
  }

  private async broadcast(userId: string) {
    const [view] = await this.views([userId]);
    if (view) await this.publisher.toRooms([`presence:${userId}`], 'presence', view);
  }
}
