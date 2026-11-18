import { Inject, Injectable } from '@nestjs/common';
import type { UserRole, UserStatus } from '@prisma/client';
import type Redis from 'ioredis';
import { isUniqueViolation, PrismaService } from '../prisma/prisma.service';
import { REDIS } from '../redis/redis.module';
import type { VerifiedToken } from './token-verifier';

export interface ProvisionedUser {
  id: string;
  role: UserRole;
  status: UserStatus;
  emailVerified: boolean;
}

const CACHE_TTL_SECONDS = 300;
const cacheKey = (uid: string) => `auth:user:${uid}`;

/** Firebase phone numbers are E.164 ("+2348012345678"); stored as digits only, like the legacy app. */
export function normalizePhone(raw: string | undefined | null): string | undefined {
  if (!raw) return undefined;
  const digits = raw.replace(/\D/g, '');
  return digits.length >= 7 && digits.length <= 15 ? digits : undefined;
}

/**
 * Maps a verified Firebase identity to the PostgreSQL user row, creating it (with profile and settings)
 * on the first authenticated request. The hot path is a Redis hit; the DB is touched only on a cache miss
 * or when token claims (email, verification, verified phone) changed.
 */
@Injectable()
export class UserProvisioningService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async resolve(token: VerifiedToken): Promise<ProvisionedUser> {
    const cached = await this.redis.get(cacheKey(token.uid)).catch(() => null);
    if (cached) {
      const user = JSON.parse(cached) as ProvisionedUser & { email?: string; phone?: string };
      if (user.emailVerified === token.emailVerified && user.email === token.email && user.phone === normalizePhone(token.phoneNumber)) {
        return user;
      }
    }
    const user = await this.upsert(token);
    await this.cache(token, user);
    return user;
  }

  /** Drop the cached identity after role/status changes so the next request sees them. */
  async invalidate(firebaseUid: string): Promise<void> {
    await this.redis.del(cacheKey(firebaseUid));
  }

  private async cache(token: VerifiedToken, user: ProvisionedUser) {
    const value = JSON.stringify({ ...user, email: token.email, phone: normalizePhone(token.phoneNumber) });
    await this.redis.set(cacheKey(token.uid), value, 'EX', CACHE_TTL_SECONDS).catch(() => undefined);
  }

  private async upsert(token: VerifiedToken): Promise<ProvisionedUser> {
    const verifiedPhone = normalizePhone(token.phoneNumber);
    const select = { id: true, role: true, status: true, emailVerified: true } as const;

    // Claims from the token are authoritative; a verified phone overrides a self-declared one.
    const claimUpdate = {
      email: token.email ?? null,
      emailVerified: token.emailVerified,
      ...(verifiedPhone ? { phoneNumber: verifiedPhone, phoneVerified: true } : {}),
    };

    const existing = await this.prisma.user.findUnique({ where: { firebaseUid: token.uid }, select: { ...select, email: true, phoneNumber: true, phoneVerified: true } });
    if (existing) {
      const changed =
        existing.email !== claimUpdate.email ||
        existing.emailVerified !== claimUpdate.emailVerified ||
        (verifiedPhone !== undefined && (existing.phoneNumber !== verifiedPhone || !existing.phoneVerified));
      if (!changed) return { id: existing.id, role: existing.role, status: existing.status, emailVerified: existing.emailVerified };
      return this.prisma.user.update({ where: { id: existing.id }, data: claimUpdate, select });
    }

    // Concurrent first requests race here. Prisma's upsert with nested creates is not a native
    // ON CONFLICT, so the loser gets a unique violation on firebase_uid: re-read the winner's row.
    try {
      return await this.prisma.user.upsert({
      where: { firebaseUid: token.uid },
      update: claimUpdate,
      create: {
        firebaseUid: token.uid,
        ...claimUpdate,
        profile: { create: { displayName: defaultDisplayName(token) } },
        settings: { create: {} },
      },
      select,
    });
    } catch (error) {
      if (!isUniqueViolation(error, 'firebase_uid')) throw error;
      return this.prisma.user.findUniqueOrThrow({ where: { firebaseUid: token.uid }, select });
    }
  }
}

function defaultDisplayName(token: VerifiedToken): string {
  const name = token.name?.trim();
  if (name) return name.slice(0, 50);
  const local = token.email?.split('@')[0]?.trim();
  return local ? local.slice(0, 50) : 'MyBuddy user';
}
