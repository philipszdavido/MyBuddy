import { InjectQueue } from '@nestjs/bullmq';
import { CanActivate, ExecutionContext, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { Queue } from 'bullmq';
import type Redis from 'ioredis';
import { AnalyticsEventJob, Q } from '../queues/queues';
import { REDIS } from '../redis/redis.module';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import type { Request } from 'express';
import { AppError } from '../common/errors/app-error';
import {
  ALLOW_SUSPENDED,
  AuthContext,
  CHECK_REVOKED,
  IS_PUBLIC,
  ROLES,
} from '../common/decorators/auth.decorators';
import { TokenVerifier } from './token-verifier';
import { UserProvisioningService } from './user-provisioning.service';

const ROLE_RANK: Record<UserRole, number> = { USER: 0, MODERATOR: 1, ADMIN: 2 };

export function bearerToken(header: string | undefined): string | undefined {
  return header?.match(/^Bearer\s+(\S+)\s*$/i)?.[1];
}

export function hasRole(actual: UserRole, required: UserRole[]): boolean {
  return required.some((r) => ROLE_RANK[actual] >= ROLE_RANK[r]);
}

/**
 * Global guard: every route is authenticated unless marked @Public(). Identity comes only from the
 * verified Firebase ID token; any user id in the request body/path is treated as data, not identity.
 */
@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly verifier: TokenVerifier,
    private readonly provisioning: UserProvisioningService,
    @Inject(REDIS) private readonly redis: Redis,
    @InjectQueue(Q.analytics) private readonly analytics: Queue<AnalyticsEventJob>,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true; // WebSocket auth happens in the gateway handshake
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const req = context.switchToHttp().getRequest<Request & { auth?: AuthContext }>();
    const token = bearerToken(req.headers.authorization);
    if (!token) throw AppError.unauthenticated();

    const checkRevoked = this.reflector.getAllAndOverride<boolean>(CHECK_REVOKED, targets) ?? false;
    const verified = await this.verifier.verify(token, checkRevoked);
    const user = await this.provisioning.resolve(verified);

    if (user.status === 'DELETING') throw AppError.unauthenticated('Account is being deleted');
    if (user.status === 'SUSPENDED' && !this.reflector.getAllAndOverride<boolean>(ALLOW_SUSPENDED, targets)) {
      throw new AppError('ACCOUNT_SUSPENDED', 'This account is suspended', HttpStatus.FORBIDDEN);
    }

    const roles = this.reflector.getAllAndOverride<UserRole[]>(ROLES, targets);
    if (roles?.length && !hasRole(user.role, roles)) throw AppError.forbidden();

    req.auth = { userId: user.id, firebaseUid: verified.uid, role: user.role, emailVerified: verified.emailVerified };
    await this.trackActive(user.id);
    return true;
  }

  /** Daily-active tracking for analytics: one Redis SET NX per user per day, one event per day. */
  private async trackActive(userId: string) {
    const day = new Date().toISOString().slice(0, 10);
    try {
      const first = await this.redis.set(`active:${userId}:${day}`, '1', 'EX', 2 * 86400, 'NX');
      if (first) await this.analytics.add('event', { userId, type: 'session.active' });
    } catch {
      // analytics must never block a request
    }
  }
}
