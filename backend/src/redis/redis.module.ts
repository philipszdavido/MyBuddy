import { Global, Inject, Injectable, Module, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import type { Env } from '../config/env';

export const REDIS = Symbol('REDIS');

/** Builds an ioredis client. BullMQ requires maxRetriesPerRequest = null on its connections. */
export function createRedis(url: string, forBullmq = false): Redis {
  return new Redis(url, {
    maxRetriesPerRequest: forBullmq ? null : 3,
    enableReadyCheck: true,
    lazyConnect: false,
  });
}

@Injectable()
class RedisLifecycle implements OnModuleDestroy {
  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async onModuleDestroy() {
    await this.redis.quit().catch(() => this.redis.disconnect());
  }
}

@Global()
@Module({
  providers: [
    {
      provide: REDIS,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) => createRedis(config.get('REDIS_URL', { infer: true })),
    },
    RedisLifecycle,
  ],
  exports: [REDIS],
})
export class RedisModule {}
