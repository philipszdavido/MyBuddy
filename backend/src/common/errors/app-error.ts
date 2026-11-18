import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Stable, client-facing error codes. The iOS client switches on `code`, never on `message`.
 * Messages are safe to show; they never contain internal details.
 */
export type ErrorCode =
  | 'VALIDATION_FAILED'
  | 'UNAUTHENTICATED'
  | 'TOKEN_REVOKED'
  | 'FORBIDDEN'
  | 'ACCOUNT_SUSPENDED'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'USERNAME_TAKEN'
  | 'RATE_LIMITED'
  | 'BLOCKED'
  | 'PRIVATE_ACCOUNT'
  | 'UNSUPPORTED_MEDIA'
  | 'MEDIA_TOO_LARGE'
  | 'MEDIA_NOT_READY'
  | 'PAYLOAD_TOO_LARGE'
  | 'INTERNAL';

export class AppError extends HttpException {
  constructor(
    readonly code: ErrorCode,
    message: string,
    status: HttpStatus,
    readonly details?: Record<string, unknown>,
  ) {
    super({ code, message, details }, status);
  }

  static notFound(what = 'Resource') {
    return new AppError('NOT_FOUND', `${what} not found`, HttpStatus.NOT_FOUND);
  }

  static forbidden(message = 'You are not allowed to do that') {
    return new AppError('FORBIDDEN', message, HttpStatus.FORBIDDEN);
  }

  static conflict(message: string, code: ErrorCode = 'CONFLICT') {
    return new AppError(code, message, HttpStatus.CONFLICT);
  }

  static badRequest(message: string, details?: Record<string, unknown>) {
    return new AppError('VALIDATION_FAILED', message, HttpStatus.BAD_REQUEST, details);
  }

  static unauthenticated(message = 'Authentication required', code: ErrorCode = 'UNAUTHENTICATED') {
    return new AppError(code, message, HttpStatus.UNAUTHORIZED);
  }
}
