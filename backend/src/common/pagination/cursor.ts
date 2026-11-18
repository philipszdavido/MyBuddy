import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { AppError } from '../errors/app-error';

/**
 * Opaque keyset cursors. Clients treat them as strings; the server encodes the sort key plus a unique
 * tiebreaker so rows sharing a timestamp are never skipped or repeated (OFFSET is never used).
 */
export function encodeCursor(parts: Record<string, string | number>): string {
  return Buffer.from(JSON.stringify(parts), 'utf8').toString('base64url');
}

export function decodeCursor<T extends Record<string, string | number>>(cursor: string, keys: (keyof T)[]): T {
  try {
    const value = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown;
    if (typeof value !== 'object' || value === null) throw new Error('not an object');
    for (const key of keys) {
      const v = (value as Record<string, unknown>)[key as string];
      if (typeof v !== 'string' && typeof v !== 'number') throw new Error(`missing ${String(key)}`);
    }
    return value as T;
  } catch {
    throw AppError.badRequest('Invalid cursor');
  }
}

/** Cursor = (ISO timestamp, id), for lists sorted newest first. */
export type TimeCursor = { t: string; id: string };

export function timeCursor(date: Date, id: string): string {
  return encodeCursor({ t: date.toISOString(), id });
}

export function parseTimeCursor(cursor: string | undefined): { date: Date; id: string } | undefined {
  if (!cursor) return undefined;
  const c = decodeCursor<TimeCursor>(cursor, ['t', 'id']);
  const date = new Date(c.t);
  if (Number.isNaN(date.getTime())) throw AppError.badRequest('Invalid cursor');
  return { date, id: c.id };
}

export class PageQuery {
  @ApiPropertyOptional({ description: 'Opaque cursor from a previous page' })
  @IsOptional() @IsString() @MaxLength(512)
  cursor?: string;

  @ApiPropertyOptional({ minimum: 1, maximum: 100, default: 20 })
  @IsOptional() @Transform(({ value }) => (value === undefined ? undefined : Number(value)))
  @IsInt() @Min(1) @Max(100)
  limit?: number;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

/**
 * Fetch `limit + 1` rows, then call this: it trims the probe row and builds the next cursor
 * from the last returned item.
 */
export function toPage<R, T>(rows: R[], limit: number, map: (row: R) => T, cursorOf: (row: R) => string): Page<T> {
  const hasMore = rows.length > limit;
  const kept = hasMore ? rows.slice(0, limit) : rows;
  return { items: kept.map(map), nextCursor: hasMore && kept.length ? cursorOf(kept[kept.length - 1]) : null };
}

export const DEFAULT_PAGE = 20;
