import { Body, Controller, Get, HttpCode, Module, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { AuthUser, CurrentUser } from '../../common/auth.decorators';
import { CursorQuery } from '../../common/pagination';
import { AuthModule } from '../auth/auth.module';
import { MessagesQuery, OpenConversationDto, SendMessageDto } from './chat.dto';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';

@ApiTags('chat')
@ApiBearerAuth()
@Controller('conversations')
class ChatController {
  constructor(private readonly chat: ChatService) {}

  /** Opens (or returns the existing) conversation about a listing/job/service/candidate. */
  @Post()
  @HttpCode(200)
  open(@CurrentUser() user: AuthUser, @Body() dto: OpenConversationDto) {
    return this.chat.open(user, dto);
  }

  @Get()
  list(@CurrentUser() user: AuthUser, @Query() query: CursorQuery) {
    return this.chat.list(user.userId, query.cursor, query.limit);
  }

  @Get('unread-count')
  async unread(@CurrentUser() user: AuthUser) {
    return { count: await this.chat.unreadTotal(user.userId) };
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.chat.get(user.userId, id);
  }

  @Get(':id/messages')
  messages(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: MessagesQuery,
  ) {
    return this.chat.messages(user.userId, id, query.cursor, query.limit);
  }

  /** REST fallback for sending; the socket `message:send` event is equivalent. */
  @Post(':id/messages')
  send(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SendMessageDto) {
    return this.chat.send(user, id, dto);
  }

  @Post(':id/read')
  @HttpCode(200)
  read(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.chat.markRead(user.userId, id);
  }

  @Post(':id/delivered')
  @HttpCode(200)
  delivered(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.chat.markDelivered(user.userId, id);
  }

  @Post(':id/archive')
  @HttpCode(200)
  async archive(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.chat.archive(user.userId, id);
    return { ok: true };
  }
}

@Module({
  imports: [AuthModule],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway],
  exports: [ChatService],
})
export class ChatModule {}
