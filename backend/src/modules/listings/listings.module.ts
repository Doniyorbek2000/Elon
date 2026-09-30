import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Module,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';

import { AuthUser, CurrentUser, MaybeUser, OptionalAuth, Roles } from '../../common/auth.decorators';
import { CursorQuery } from '../../common/pagination';
import {
  ChangeStatusDto,
  CreateListingDto,
  FeedQuery,
  MyListingsQuery,
  RejectDto,
  UpdateListingDto,
} from './listings.dto';
import { ListingsService } from './listings.service';

@ApiTags('listings')
@Controller()
class ListingsController {
  constructor(private readonly listings: ListingsService) {}

  @OptionalAuth()
  @Get('listings')
  feed(@Query() query: FeedQuery, @MaybeUser() viewer?: AuthUser) {
    return this.listings.feed(query, viewer);
  }

  @OptionalAuth()
  @Post('listings/:id/share')
  @HttpCode(200)
  share(@Param('id', ParseUUIDPipe) id: string, @Req() request: Request, @MaybeUser() viewer?: AuthUser) {
    return this.listings.recordShare(id, viewer?.userId ?? `${request.ip ?? 'unknown'}`);
  }

  @OptionalAuth()
  @Get('listings/:id')
  detail(@Param('id', ParseUUIDPipe) id: string, @Req() request: Request, @MaybeUser() viewer?: AuthUser) {
    return this.listings.detail(id, viewer, viewer?.userId ?? request.ip);
  }

  @OptionalAuth()
  @Get('listings/:id/similar')
  similar(@Param('id', ParseUUIDPipe) id: string, @MaybeUser() viewer?: AuthUser) {
    return this.listings.similar(id, viewer);
  }

  @ApiBearerAuth()
  @Post('listings')
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateListingDto) {
    return this.listings.create(user, dto);
  }

  @ApiBearerAuth()
  @Patch('listings/:id')
  update(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: UpdateListingDto,
  ) {
    return this.listings.update(user, id, dto);
  }

  @ApiBearerAuth()
  @Post('listings/:id/publish')
  @HttpCode(200)
  publish(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.listings.publish(user, id);
  }

  @ApiBearerAuth()
  @Post('listings/:id/status')
  @HttpCode(200)
  status(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ChangeStatusDto,
  ) {
    return this.listings.changeStatus(user, id, dto.status);
  }

  @ApiBearerAuth()
  @Delete('listings/:id')
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.listings.remove(user, id);
    return { ok: true };
  }

  @ApiBearerAuth()
  @Post('listings/:id/contact')
  @HttpCode(200)
  contact(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.listings.contact(user, id);
  }

  @ApiBearerAuth()
  @Get('me/listings')
  mine(@CurrentUser() user: AuthUser, @Query() query: MyListingsQuery) {
    return this.listings.mine(user.userId, query);
  }
}

/** Moderator-only endpoints; roles are assigned in the database, never via the API. */
@ApiTags('moderation')
@ApiBearerAuth()
@Roles('MODERATOR', 'ADMIN')
@Controller('moderation/listings')
class ListingModerationController {
  constructor(private readonly listings: ListingsService) {}

  @Get()
  queue(@Query() query: CursorQuery) {
    return this.listings.moderationQueue(query.cursor, query.limit);
  }

  @Post(':id/approve')
  @HttpCode(200)
  approve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.listings.moderate(user, id, 'approve');
  }

  @Post(':id/reject')
  @HttpCode(200)
  reject(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RejectDto) {
    return this.listings.moderate(user, id, 'reject', dto.reason);
  }
}

@Module({
  controllers: [ListingsController, ListingModerationController],
  providers: [ListingsService],
  exports: [ListingsService],
})
export class ListingsModule {}
