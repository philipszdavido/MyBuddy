import { ExecutionContext, Inject, Injectable } from '@nestjs/common';
import { ThrottlerGuard, ThrottlerStorage } from '@nestjs/throttler';
import type Redis from 'ioredis';
import { REDIS } from '../redis/redis.module';
import type { AuthContext } from './decorators/auth.decorators';

interface ThrottlerStorageRecord {
  totalHits: number;
  timeToExpire: number;
  isBlocked: boolean;
  timeToBlockExpire: number;
}

// Fixed window counter + optional block, atomic in one round trip. Times in milliseconds.
const SCRIPT = `
local hits = redis.call('INCR', KEYS[1])
if hits == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
local ttl = redis.call('PTTL', KEYS[1])
local blockTtl = redis.call('PTTL', KEYS[2])
if blockTtl <= 0 and hits > tonumber(ARGV[2]) then
  redis.call('SET', KEYS[2], '1', 'PX', ARGV[3])
  blockTtl = tonumber(ARGV[3])
end
return { hits, ttl, blockTtl }
`;

/** Shared across API instances so limits hold when scaled horizontally. */
@Injectable()
export class RedisThrottlerStorage implements ThrottlerStorage {
  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async increment(key: string, ttl: number, limit: number, blockDuration: number, throttlerName: string): Promise<ThrottlerStorageRecord> {
    const base = `rl:${throttlerName}:${key}`;
    const [hits, timeToExpire, blockTtl] = (await this.redis.eval(SCRIPT, 2, base, `${base}:blocked`, ttl, limit, blockDuration || ttl)) as [number, number, number];
    const isBlocked = blockTtl > 0;
    return {
      totalHits: hits,
      timeToExpire: Math.max(0, Math.ceil(timeToExpire / 1000)),
      isBlocked,
      timeToBlockExpire: isBlocked ? Math.ceil(blockTtl / 1000) : 0,
    };
  }
}

/** Rate-limits per authenticated user (falls back to IP), so users behind one NAT don't share a budget. */
@Injectable()
export class UserThrottlerGuard extends ThrottlerGuard {
  protected override async getTracker(req: Record<string, unknown>): Promise<string> {
    const auth = req.auth as AuthContext | undefined;
    return auth ? `u:${auth.userId}` : `ip:${String(req.ip)}`;
  }

  protected override shouldSkip(context: ExecutionContext): Promise<boolean> {
    return Promise.resolve(context.getType() !== 'http');
  }
}
