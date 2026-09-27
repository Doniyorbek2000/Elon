import { Body, Controller, Delete, Get, Global, HttpCode, Module, Param, ParseUUIDPipe, Patch, Post, Query, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';

import { AuthUser, CurrentUser, MaybeUser, OptionalAuth, Public } from '../../common/auth.decorators';
import { AdEventDto, AddMemberDto, AdsQuery, BusinessDto, CampaignDto, StatsQuery, StorefrontListingsQuery, UpdateBusinessDto } from './business.dto';
import { AdsService } from './ads.service';
import { AnalyticsService } from './analytics.service';
import { BusinessService } from './business.service';

@ApiTags('business')
@Controller()
class BusinessController {
  constructor(
    private readonly business: BusinessService,
    private readonly ads: AdsService,
    private readonly analytics: AnalyticsService,
  ) {}

  @ApiBearerAuth()
  @Post('businesses')
  create(@CurrentUser() user: AuthUser, @Body() dto: BusinessDto) {
    return this.business.create(user, dto);
  }

  @ApiBearerAuth()
  @Get('me/business')
  mine(@CurrentUser() user: AuthUser) {
    return this.business.mine(user.userId);
  }

  @ApiBearerAuth()
  @Patch('me/business')
  update(@CurrentUser() user: AuthUser, @Body() dto: UpdateBusinessDto) {
    return this.business.update(user.userId, dto);
  }

  @ApiBearerAuth()
  @Post('me/business/verification')
  @HttpCode(200)
  requestVerification(@CurrentUser() user: AuthUser) {
    return this.business.requestVerification(user.userId);
  }

  @ApiBearerAuth()
  @Post('me/business/members')
  addManager(@CurrentUser() user: AuthUser, @Body() dto: AddMemberDto) {
    return this.business.addManager(user.userId, dto);
  }

  @ApiBearerAuth()
  @Delete('me/business/members/:userId')
  removeManager(@CurrentUser() user: AuthUser, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.business.removeManager(user.userId, userId);
  }

  /** Public storefront (deep link: /business/:id). */
  @Public()
  @Get('businesses/:id')
  storefront(@Param('id', ParseUUIDPipe) id: string) {
    return this.business.storefront(id);
  }

  @Public()
  @Get('businesses/:id/listings')
  storefrontListings(@Param('id', ParseUUIDPipe) id: string, @Query() query: StorefrontListingsQuery) {
    return this.business.storefrontListings(id, query.cursor, query.limit);
  }

  // ─── ads

  @ApiBearerAuth()
  @Post('me/business/campaigns')
  createCampaign(@CurrentUser() user: AuthUser, @Body() dto: CampaignDto) {
    return this.ads.create(user.userId, dto);
  }

  @ApiBearerAuth()
  @Get('me/business/campaigns')
  campaigns(@CurrentUser() user: AuthUser) {
    return this.ads.mine(user.userId);
  }

  @ApiBearerAuth()
  @Post('me/business/campaigns/:id/pause')
  @HttpCode(200)
  pause(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.ads.setPaused(user.userId, id, true);
  }

  @ApiBearerAuth()
  @Post('me/business/campaigns/:id/resume')
  @HttpCode(200)
  resume(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.ads.setPaused(user.userId, id, false);
  }

  @Public()
  @Get('ads')
  serve(@Query() query: AdsQuery) {
    return this.ads.serve(query);
  }

  /** Aggregated impression/click; duplicates per viewer/day are ignored. */
  @OptionalAuth()
  @Post('ads/:id/events')
  @HttpCode(200)
  adEvent(@Param('id', ParseUUIDPipe) id: string, @Body() dto: AdEventDto, @Req() request: Request, @MaybeUser() viewer?: AuthUser) {
    const key = viewer?.userId ?? `${request.ip ?? 'unknown'}|${request.headers['user-agent'] ?? ''}`;
    return this.ads.recordEvent(id, dto.type, key);
  }

  // ─── seller analytics

  @ApiBearerAuth()
  @Get('me/listings/:id/stats')
  listingStats(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() query: StatsQuery) {
    return this.analytics.listingStats(user.userId, id, query);
  }

  @ApiBearerAuth()
  @Get('me/promotions/:id/stats')
  promotionStats(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.analytics.promotionStats(user.userId, id);
  }
}

@Global()
@Module({
  controllers: [BusinessController],
  providers: [BusinessService, AdsService, AnalyticsService],
  exports: [BusinessService, AdsService, AnalyticsService],
})
export class BusinessModule {}
