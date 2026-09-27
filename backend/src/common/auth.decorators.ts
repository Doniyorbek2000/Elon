import { ExecutionContext, SetMetadata, createParamDecorator } from '@nestjs/common';
import type { UserRole } from '@prisma/client';

import { AppError } from './errors';

/** Identity attached to a request by the auth guard. Never client-supplied. */
export interface AuthUser {
  userId: string;
  sessionId: string;
  role: UserRole;
}

export const IS_PUBLIC = 'auth:public';
export const IS_OPTIONAL_AUTH = 'auth:optional';
export const ROLES = 'auth:roles';

/** No token required. */
export const Public = (): MethodDecorator & ClassDecorator => SetMetadata(IS_PUBLIC, true);

/** Token optional: used to personalize (e.g. `isFavorite`) public resources. */
export const OptionalAuth = (): MethodDecorator & ClassDecorator => SetMetadata(IS_OPTIONAL_AUTH, true);

export const Roles = (...roles: UserRole[]): MethodDecorator & ClassDecorator => SetMetadata(ROLES, roles);

export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): AuthUser => {
  const user = context.switchToHttp().getRequest<{ user?: AuthUser }>().user;
  if (!user) throw AppError.unauthenticated();
  return user;
});

export const MaybeUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthUser | undefined =>
    context.switchToHttp().getRequest<{ user?: AuthUser }>().user,
);
