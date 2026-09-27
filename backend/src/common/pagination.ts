import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

import { AppError } from './errors';

export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 50;

/** Opaque cursor: base64url JSON. Clients must treat it as a token. */
export function encodeCursor(value: Record<string, string | number>): string {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

export function decodeCursor<T extends Record<string, string | number>>(cursor: string | undefined): T | undefined {
  if (!cursor) return undefined;
  try {
    const parsed: unknown = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (parsed && typeof parsed === 'object') return parsed as T;
  } catch {
    // fall through
  }
  throw AppError.validation('Invalid cursor');
}

export class CursorQuery {
  @IsOptional()
  @IsString()
  @MaxLength(512)
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAGE_SIZE)
  limit?: number;
}

/** Response wrapper recognized by the envelope interceptor. */
export class Page<T> {
  constructor(
    readonly items: T[],
    readonly nextCursor: string | null,
    readonly extra: Record<string, unknown> = {},
  ) {}
}

/**
 * Keyset page over rows sorted by (date desc, id desc). Fetch `limit + 1`
 * rows; the extra one only proves another page exists.
 */
export function keysetPage<T extends { id: string }>(
  rows: T[],
  limit: number,
  dateOf: (row: T) => Date,
): { items: T[]; nextCursor: string | null } {
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const last = items[items.length - 1];
  return {
    items,
    nextCursor: hasMore && last ? encodeCursor({ t: dateOf(last).toISOString(), id: last.id }) : null,
  };
}

export function keysetWhere(cursor: string | undefined, field = 'createdAt'): Record<string, unknown> | undefined {
  const decoded = decodeCursor<{ t: string; id: string }>(cursor);
  if (!decoded) return undefined;
  const t = new Date(decoded.t);
  if (Number.isNaN(t.getTime()) || typeof decoded.id !== 'string') throw AppError.validation('Invalid cursor');
  return { OR: [{ [field]: { lt: t } }, { [field]: t, id: { lt: decoded.id } }] };
}

export function pageSize(limit: number | undefined): number {
  return Math.min(Math.max(limit ?? DEFAULT_PAGE_SIZE, 1), MAX_PAGE_SIZE);
}
