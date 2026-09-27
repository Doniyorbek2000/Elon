import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Stable machine-readable error codes. Clients map these to localized copy;
 * `message` is a developer-facing English hint and never contains internals.
 */
export type ErrorCode =
  | 'VALIDATION_FAILED'
  | 'UNAUTHENTICATED'
  | 'TOKEN_EXPIRED'
  | 'SESSION_REVOKED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMITED'
  | 'OTP_INVALID'
  | 'OTP_EXPIRED'
  | 'OTP_TOO_MANY_ATTEMPTS'
  | 'OTP_COOLDOWN'
  | 'BLOCKED'
  | 'INVALID_STATE'
  | 'PAYLOAD_TOO_LARGE'
  | 'UNSUPPORTED_MEDIA'
  | 'NOT_ELIGIBLE'
  | 'SERVICE_UNAVAILABLE'
  | 'INTERNAL';

export class AppError extends HttpException {
  constructor(
    readonly code: ErrorCode,
    message: string,
    status: HttpStatus,
    readonly details?: unknown,
  ) {
    super({ code, message, details }, status);
  }

  static notFound(what = 'Resource'): AppError {
    return new AppError('NOT_FOUND', `${what} not found`, HttpStatus.NOT_FOUND);
  }

  static forbidden(message = 'You do not have access to this resource'): AppError {
    return new AppError('FORBIDDEN', message, HttpStatus.FORBIDDEN);
  }

  static unauthenticated(message = 'Authentication required', code: ErrorCode = 'UNAUTHENTICATED'): AppError {
    return new AppError(code, message, HttpStatus.UNAUTHORIZED);
  }

  static validation(message: string, details?: unknown): AppError {
    return new AppError('VALIDATION_FAILED', message, HttpStatus.UNPROCESSABLE_ENTITY, details);
  }

  static conflict(message: string): AppError {
    return new AppError('CONFLICT', message, HttpStatus.CONFLICT);
  }

  static invalidState(message: string): AppError {
    return new AppError('INVALID_STATE', message, HttpStatus.CONFLICT);
  }

  static rateLimited(retryAfterSeconds: number, code: ErrorCode = 'RATE_LIMITED'): AppError {
    return new AppError(code, 'Too many requests', HttpStatus.TOO_MANY_REQUESTS, { retryAfterSeconds });
  }
}
