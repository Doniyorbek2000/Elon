import {
  Body,
  Controller,
  Delete,
  Get,
  Global,
  HttpCode,
  Module,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthUser, CurrentUser, Public } from '../../common/auth.decorators';
import {
  AddMemberDto,
  BusinessDto,
  StatsQuery,
  StorefrontListingsQuery,
  UpdateBusinessDto,
} from './business.dto';
import { AnalyticsService } from './analytics.service';
import { BusinessService } from './business.service';

@ApiTags('business')
@Controller()
class BusinessController {
  constructor(
    private readonly business: BusinessService,
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

  // ─── seller analytics

  @ApiBearerAuth()
  @Get('me/listings/:id/stats')
  listingStats(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Query() query: StatsQuery,
  ) {
    return this.analytics.listingStats(user.userId, id, query);
  }
}

@Global()
@Module({
  controllers: [BusinessController],
  providers: [BusinessService, AnalyticsService],
  exports: [BusinessService, AnalyticsService],
})
export class BusinessModule {}
