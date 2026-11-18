import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import type { UserRole } from '@prisma/client';

/** The authenticated caller, resolved by FirebaseAuthGuard from the verified ID token (never from the client). */
export interface AuthContext {
  userId: string;
  firebaseUid: string;
  role: UserRole;
  emailVerified: boolean;
}

export const IS_PUBLIC = 'auth:public';
export const ROLES = 'auth:roles';
export const CHECK_REVOKED = 'auth:checkRevoked';
export const ALLOW_SUSPENDED = 'auth:allowSuspended';

/** Route needs no authentication (health checks). */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Route requires one of these roles. Admin implies moderator. */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES, roles);

/** Sensitive action: also checks the token has not been revoked (one extra Firebase round trip). */
export const SensitiveAction = () => SetMetadata(CHECK_REVOKED, true);

/** Suspended accounts may still call this route (read own profile, delete account). */
export const AllowSuspended = () => SetMetadata(ALLOW_SUSPENDED, true);

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthContext => {
  const req = ctx.switchToHttp().getRequest<{ auth?: AuthContext }>();
  if (!req.auth) throw new Error('CurrentUser used on a route without authentication');
  return req.auth;
});
