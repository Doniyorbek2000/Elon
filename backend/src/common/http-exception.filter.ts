import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { Request, Response } from 'express';

import { AppError, ErrorCode } from './errors';

interface ErrorBody {
  error: { code: ErrorCode; message: string; details?: unknown; requestId?: string };
}

const statusToCode: Record<number, ErrorCode> = {
  400: 'VALIDATION_FAILED',
  401: 'UNAUTHENTICATED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  409: 'CONFLICT',
  413: 'PAYLOAD_TOO_LARGE',
  415: 'UNSUPPORTED_MEDIA',
  422: 'VALIDATION_FAILED',
  429: 'RATE_LIMITED',
  503: 'SERVICE_UNAVAILABLE',
};

/**
 * Single error envelope for every failure:
 *   { "error": { "code", "message", "details"?, "requestId" } }
 * Unknown errors become INTERNAL without stack traces or driver messages.
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('HttpException');

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const response = http.getResponse<Response>();
    const request = http.getRequest<Request & { id?: string }>();
    const { status, body } = this.toBody(exception);
    body.error.requestId = request.id;
    if (status >= 500) {
      this.logger.error({ err: exception, requestId: request.id, path: request.path }, 'Unhandled error');
    }
    const retry = (body.error.details as { retryAfterSeconds?: number } | undefined)?.retryAfterSeconds;
    if (status === 429 && retry) response.setHeader('Retry-After', String(retry));
    response.status(status).json(body);
  }

  private toBody(exception: unknown): { status: number; body: ErrorBody } {
    if (exception instanceof AppError) {
      return {
        status: exception.getStatus(),
        body: { error: { code: exception.code, message: exception.message, details: exception.details } },
      };
    }
    if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      if (exception.code === 'P2002') {
        return { status: 409, body: { error: { code: 'CONFLICT', message: 'Resource already exists' } } };
      }
      if (exception.code === 'P2025') {
        return { status: 404, body: { error: { code: 'NOT_FOUND', message: 'Resource not found' } } };
      }
      if (exception.code === 'P2003') {
        return {
          status: 422,
          body: { error: { code: 'VALIDATION_FAILED', message: 'Referenced resource does not exist' } },
        };
      }
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const raw = exception.getResponse();
      const message =
        typeof raw === 'string' ? raw : ((raw as { message?: unknown }).message ?? exception.message);
      const details = Array.isArray(message) ? { fields: message } : undefined;
      return {
        status,
        body: {
          error: {
            code: statusToCode[status] ?? (status >= 500 ? 'INTERNAL' : 'VALIDATION_FAILED'),
            message: Array.isArray(message)
              ? 'Validation failed'
              : typeof message === 'string'
                ? message
                : exception.message,
            details,
          },
        },
      };
    }
    return {
      status: HttpStatus.INTERNAL_SERVER_ERROR,
      body: { error: { code: 'INTERNAL', message: 'Internal server error' } },
    };
  }
}
