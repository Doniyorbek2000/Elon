import { Body, Controller, Delete, Get, Global, HttpCode, Module, Param, ParseUUIDPipe, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

import { AuthUser, CurrentUser } from '../../common/auth.decorators';
import { CursorQuery } from '../../common/pagination';
import { NotificationsService } from './notifications.service';
import { PUSH_PROVIDER, createPushProvider } from './push.provider';

class RegisterDeviceDto {
  @IsString()
  @Length(20, 4096)
  token!: string;

  @IsIn(['android', 'ios', 'web', 'other'])
  platform!: string;

  @IsOptional()
  @IsString()
  @MaxLength(16)
  locale?: string;
}

class UnregisterDeviceDto {
  @IsString()
  @Length(20, 4096)
  token!: string;
}

@ApiTags('notifications')
@ApiBearerAuth()
@Controller()
class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get('notifications')
  list(@CurrentUser() user: AuthUser, @Query() query: CursorQuery) {
    return this.notifications.list(user.userId, query.cursor, query.limit);
  }

  @Get('notifications/unread-count')
  async unread(@CurrentUser() user: AuthUser) {
    return { count: await this.notifications.unreadCount(user.userId) };
  }

  @Post('notifications/:id/read')
  @HttpCode(200)
  async read(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.notifications.markRead(user.userId, id);
    return { ok: true };
  }

  @Post('notifications/read-all')
  @HttpCode(200)
  async readAll(@CurrentUser() user: AuthUser) {
    return { updated: await this.notifications.markAllRead(user.userId) };
  }

  @Put('push-devices')
  async register(@CurrentUser() user: AuthUser, @Body() dto: RegisterDeviceDto) {
    await this.notifications.registerDevice(user.userId, user.sessionId, dto.token, dto.platform, dto.locale);
    return { ok: true };
  }

  @Delete('push-devices')
  async unregister(@CurrentUser() user: AuthUser, @Body() dto: UnregisterDeviceDto) {
    await this.notifications.unregisterDevice(user.userId, dto.token);
    return { ok: true };
  }
}

@Global()
@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService, { provide: PUSH_PROVIDER, useFactory: createPushProvider }],
  exports: [NotificationsService],
})
export class NotificationsModule {}
