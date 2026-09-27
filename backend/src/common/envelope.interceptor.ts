import { CallHandler, ExecutionContext, Injectable, NestInterceptor, StreamableFile } from '@nestjs/common';
import { Observable, map } from 'rxjs';

import { Page } from './pagination';

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
        if (value instanceof Page) {
          return { data: value.items, meta: { nextCursor: value.nextCursor, ...value.extra } };
        }
        return { data: value ?? null };
      }),
    );
  }
}
