import { Global, Inject, Injectable, Logger, Module } from '@nestjs/common';
import type Redis from 'ioredis';
import { REDIS } from '../redis/redis.module';

export const REALTIME_CHANNEL = 'rt:events';

/** Server → client events (see docs/backend/REALTIME.md). */
export type RealtimeEvent =
  | 'message:new'
  | 'message:updated'
  | 'message:deleted'
  | 'message:reaction'
  | 'conversation:updated'
  | 'conversation:read'
  | 'conversation:delivered'
  | 'typing'
  | 'presence'
  | 'notification:new'
  | 'media:updated'
  /** Account suspended/deleted: sockets receive this, then are disconnected by the gateway. */
  | 'session:revoked';

export interface RealtimeEnvelope {
  /** Deliver to these users' sockets (room user:{id}) … */
  userIds?: string[];
  /** … or to subscribers of these rooms (e.g. presence:{id}). */
  rooms?: string[];
  event: RealtimeEvent;
  payload: unknown;
}

/**
 * Publishes real-time events through Redis. Works from the API and from workers; every API instance's
 * gateway subscribes and emits to its *local* sockets only, so each socket receives an event exactly once
 * no matter how many instances run. Delivery is best-effort: clients re-sync from PostgreSQL (the source
 * of truth) on reconnect, so a missed event is never a lost message.
 */
@Injectable()
export class RealtimePublisher {
  private readonly logger = new Logger(RealtimePublisher.name);

  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async toUsers(userIds: string[], event: RealtimeEvent, payload: unknown): Promise<void> {
    if (userIds.length === 0) return;
    await this.publish({ userIds: [...new Set(userIds)], event, payload });
  }

  async toRooms(rooms: string[], event: RealtimeEvent, payload: unknown): Promise<void> {
    if (rooms.length === 0) return;
    await this.publish({ rooms, event, payload });
  }

  private async publish(envelope: RealtimeEnvelope) {
    try {
      await this.redis.publish(REALTIME_CHANNEL, JSON.stringify(envelope));
    } catch (error) {
      this.logger.warn(`realtime publish failed (${envelope.event}): ${String(error)}`);
    }
  }
}

@Global()
@Module({ providers: [RealtimePublisher], exports: [RealtimePublisher] })
export class RealtimeCoreModule {}
