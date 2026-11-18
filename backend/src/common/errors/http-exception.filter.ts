import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import { Prisma } from '@prisma/client';
import type { Request, Response } from 'express';
import { AppError, ErrorCode } from './app-error';

export interface ErrorBody {
  error: { code: ErrorCode; message: string; details?: Record<string, unknown>; requestId?: string };
}

const STATUS_CODES: Partial<Record<number, ErrorCode>> = {
  400: 'VALIDATION_FAILED',
  401: 'UNAUTHENTICATED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  409: 'CONFLICT',
  413: 'PAYLOAD_TOO_LARGE',
  429: 'RATE_LIMITED',
};

/** Maps any thrown value to the one error envelope: `{ error: { code, message, details?, requestId } }`. */
export function toErrorBody(exception: unknown, requestId?: string): { status: number; body: ErrorBody } {
  if (exception instanceof AppError) {
    return {
      status: exception.getStatus(),
      body: { error: { code: exception.code, message: exception.message, details: exception.details, requestId } },
    };
  }
  if (exception instanceof ThrottlerException) {
    return { status: 429, body: { error: { code: 'RATE_LIMITED', message: 'Too many requests', requestId } } };
  }
  if (exception instanceof HttpException) {
    const status = exception.getStatus();
    const response = exception.getResponse();
    // ValidationPipe errors arrive as { message: string[] }
    const raw = typeof response === 'object' && response !== null ? (response as Record<string, unknown>).message : response;
    const messages = Array.isArray(raw) ? raw.map(String) : undefined;
    const message = messages ? 'Request validation failed' : typeof raw === 'string' ? raw : exception.message;
    return {
      status,
      body: {
        error: {
          code: STATUS_CODES[status] ?? (status >= 500 ? 'INTERNAL' : 'VALIDATION_FAILED'),
          message: status >= 500 ? 'Something went wrong' : message,
          details: messages ? { fields: messages } : undefined,
          requestId,
        },
      },
    };
  }
  if (exception instanceof Prisma.PrismaClientKnownRequestError) {
    if (exception.code === 'P2025') {
      return { status: 404, body: { error: { code: 'NOT_FOUND', message: 'Resource not found', requestId } } };
    }
    if (exception.code === 'P2002') {
      return { status: 409, body: { error: { code: 'CONFLICT', message: 'Already exists', requestId } } };
    }
  }
  return {
    status: HttpStatus.INTERNAL_SERVER_ERROR,
    body: { error: { code: 'INTERNAL', message: 'Something went wrong', requestId } },
  };
}

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    if (host.getType() !== 'http') throw exception;
    const ctx = host.switchToHttp();
    const req = ctx.getRequest<Request & { id?: string }>();
    const res = ctx.getResponse<Response>();
    const { status, body } = toErrorBody(exception, req.id ? String(req.id) : undefined);
    if (status >= 500) {
      this.logger.error({ err: exception, requestId: req.id, path: req.path }, 'Unhandled error');
    }
    res.status(status).json(body);
  }
}
