import { BullModule } from '@nestjs/bullmq';
import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { DefaultJobOptions } from 'bullmq';
import type { Env } from '../config/env';
import { createRedis } from '../redis/redis.module';

/** Every background queue. The API only enqueues; workers (src/worker.ts) consume. */
export const Q = {
  feed: 'feed-fanout',
  notifications: 'notifications',
  email: 'email',
  media: 'media-image',
  video: 'media-video',
  search: 'search-index',
  analytics: 'analytics',
  cleanup: 'cleanup',
  accountDeletion: 'account-deletion',
} as const;

export type QueueName = (typeof Q)[keyof typeof Q];

/** Retries with exponential backoff; completed jobs are trimmed, failed jobs kept for inspection. */
export const DEFAULT_JOB_OPTIONS: DefaultJobOptions = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2000 },
  removeOnComplete: { age: 24 * 3600, count: 1000 },
  removeOnFail: { age: 14 * 24 * 3600 },
};

/** Lower number = higher priority (BullMQ semantics). */
export const PRIORITY = { realtime: 1, normal: 5, bulk: 10 } as const;

// Job payloads (ids only: workers re-read current state, so a job never acts on stale data).
export interface FanoutPostJob { postId: string }
export interface RetractPostJob { postId: string }
export interface BackfillFollowJob { followerId: string; followeeId: string }
export interface UnfollowJob { followerId: string; followeeId: string }
export interface DeliverNotificationJob { notificationId: string }
export interface ProcessMediaJob { mediaId: string }
export interface AccountDeletionJob { userId: string; firebaseUid: string }
export interface AnalyticsEventJob { userId?: string; type: string; entityId?: string; properties?: Record<string, string | number | boolean> }
export interface ImpressionsJob { userId: string; postIds: string[] }
export interface EmailJob { to: string; template: 'account-deleted' | 'report-received'; data?: Record<string, string> }

const ALL = Object.values(Q);

@Global()
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) => ({
        connection: createRedis(config.get('REDIS_URL', { infer: true }), true),
        prefix: 'mb',
        defaultJobOptions: DEFAULT_JOB_OPTIONS,
      }),
    }),
    BullModule.registerQueue(...ALL.map((name) => ({ name }))),
  ],
  exports: [BullModule],
})
export class QueuesModule {}
