import { CallHandler, ExecutionContext, Injectable, NestInterceptor, StreamableFile } from '@nestjs/common';
import { Observable, map } from 'rxjs';

import { Page } from './pagination';

/**
 * Wraps a response that must reach the client exactly as given, without the
 * `{ data }` envelope. Third parties (payment providers) dictate their own
 * response formats for callbacks.
 */
export class RawResponse {
  constructor(readonly body: unknown) {}
}

/**
 * Success envelope:
 *   { "data": ... }                                   single resource / action
 *   { "data": [...], "meta": { "nextCursor", ... } }  paginated list
 */
@Injectable()
export class EnvelopeInterceptor implements NestInterceptor {
  intercept(_context: ExecutionContext, next: CallHandler): Observable<unknown> {
    return next.handle().pipe(
      map((value: unknown) => {
        if (value instanceof StreamableFile) return value;
        if (value instanceof RawResponse) return value.body;
        if (value instanceof Page) {
          return { data: value.items, meta: { nextCursor: value.nextCursor, ...value.extra } };
        }
        return { data: value ?? null };
      }),
    );
  }
}
