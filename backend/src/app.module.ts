import { Module, RequestMethod } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import type Redis from 'ioredis';
import { randomUUID } from 'node:crypto';
import { LoggerModule } from 'nestjs-pino';
import { FirebaseAuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { AuditModule } from './common/audit.service';
import { RedisThrottlerStorage, UserThrottlerGuard } from './common/throttle';
import { validateEnv } from './config/env';
import { GraphCoreModule } from './graph/graph-core.module';
import { HealthModule } from './health/health.controller';
import { MediaCoreModule } from './media/media-core.module';
import { PrismaModule } from './prisma/prisma.service';
import { QueuesModule } from './queues/queues';
import { REDIS, RedisModule } from './redis/redis.module';
import { UsersModule } from './users/users.module';
import { UsersCoreModule } from './users/users-core.module';
import { NotificationsCoreModule } from './notifications/notification-writer.service';
import { GraphModule } from './graph/graph.module';
import { ContentModule } from './posts/content.module';
import { FeedModule } from './feed/feed.controller';
import { MediaModule } from './media/media.controller';
import { MessagingModule } from './messaging/messaging.controller';
import { NotificationsModule } from './notifications/notifications.controller';
import { RealtimeCoreModule } from './realtime/realtime.publisher';
import { SearchModule } from './search/search.module';
import { AnalyticsModule } from './analytics/analytics.module';
import { ModerationModule } from './moderation/moderation.module';

/** Infrastructure shared by the API and the worker process. */
export const coreImports = [
  // Tests configure everything through process.env and must not pick up a developer's .env file.
  ConfigModule.forRoot({ isGlobal: true, validate: validateEnv, cache: true, ignoreEnvFile: process.env.NODE_ENV === 'test' }),
  LoggerModule.forRoot({
    forRoutes: [{ path: '{*path}', method: RequestMethod.ALL }],
    pinoHttp: {
      level: process.env.LOG_LEVEL ?? (process.env.NODE_ENV === 'production' ? 'info' : 'debug'),
      genReqId: (req) => (typeof req.headers['x-request-id'] === 'string' ? req.headers['x-request-id'].slice(0, 64) : randomUUID()),
      // Never log credentials or message content.
      redact: ['req.headers.authorization', 'req.headers.cookie', 'req.body', 'res.headers["set-cookie"]'],
      autoLogging: { ignore: (req) => req.url?.startsWith('/health') ?? false },
      transport: process.env.NODE_ENV === 'development' ? { target: 'pino/file', options: { destination: 1 } } : undefined,
    },
  }),
  PrismaModule,
  RedisModule,
  QueuesModule,
  AuditModule,
  GraphCoreModule,
  MediaCoreModule,
  UsersCoreModule,
  NotificationsCoreModule,
  RealtimeCoreModule,
];

@Module({
  imports: [
    ...coreImports,
    ThrottlerModule.forRootAsync({
      inject: [REDIS],
      useFactory: (redis: Redis) => ({
        // Default budget per user (or IP); write-heavy routes tighten it with @Throttle().
        throttlers: [{ name: 'default', ttl: 60_000, limit: 300 }],
        storage: new RedisThrottlerStorage(redis),
      }),
    }),
    AuthModule,
    HealthModule,
    UsersModule,
    GraphModule,
    ContentModule,
    FeedModule,
    MediaModule,
    MessagingModule,
    NotificationsModule,
    SearchModule,
    AnalyticsModule,
    ModerationModule,
  ],
  providers: [
    // Order matters: authenticate first, so the throttler can key on the user id.
    { provide: APP_GUARD, useExisting: FirebaseAuthGuard },
    { provide: APP_GUARD, useClass: UserThrottlerGuard },
  ],
})
export class AppModule {}
