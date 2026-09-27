import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { Request } from 'express';

import { AuthUser, CurrentUser, Public } from '../../common/auth.decorators';
import { RefreshDto, RequestOtpDto, VerifyOtpDto } from './auth.dto';
import { AuthService, RequestMeta } from './auth.service';

const meta = (request: Request): RequestMeta => ({ ip: request.ip, userAgent: request.headers['user-agent'] });

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('otp/request')
  @HttpCode(200)
  requestOtp(@Body() dto: RequestOtpDto, @Req() request: Request) {
    return this.auth.requestOtp(dto.phone, request.ip ?? 'unknown');
  }

  @Public()
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('otp/verify')
  @HttpCode(200)
  verifyOtp(@Body() dto: VerifyOtpDto, @Req() request: Request) {
    return this.auth.verifyOtp(dto.phone, dto.code, dto.device, meta(request));
  }

  @Public()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto, @Req() request: Request) {
    return this.auth.refresh(dto.refreshToken, meta(request));
  }

  @ApiBearerAuth()
  @Post('logout')
  @HttpCode(200)
  async logout(@CurrentUser() user: AuthUser) {
    await this.auth.logout(user.userId, user.sessionId);
    return { ok: true };
  }

  @ApiBearerAuth()
  @Post('logout-all')
  @HttpCode(200)
  async logoutAll(@CurrentUser() user: AuthUser) {
    return { revokedSessions: await this.auth.logoutAll(user.userId) };
  }

  @ApiBearerAuth()
  @Get('sessions')
  sessions(@CurrentUser() user: AuthUser) {
    return this.auth.listSessions(user.userId, user.sessionId);
  }

  @ApiBearerAuth()
  @Delete('sessions/:id')
  async revoke(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.auth.revokeSession(user.userId, id);
    return { ok: true };
  }
}
