import { Body, Controller, Delete, Get, Header, HttpCode, Module, Param, ParseUUIDPipe, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';

import { AuthUser, CurrentUser, MaybeUser, OptionalAuth, Public } from '../../common/auth.decorators';
import { CursorQuery } from '../../common/pagination';
import { OfferingDto, PortfolioDto, ProviderDto, ProviderSearchQuery, ProviderStatusDto, ReviewDto } from './services.dto';
import { ServicesService } from './services.service';

@ApiTags('services')
@Controller()
class ServicesController {
  constructor(private readonly services: ServicesService) {}

  @Public()
  @Get('service-categories')
  @Header('Cache-Control', 'public, max-age=300')
  categories() {
    return this.services.categories();
  }

  @OptionalAuth()
  @Get('providers')
  search(@Query() query: ProviderSearchQuery, @MaybeUser() viewer?: AuthUser) {
    return this.services.search(query, viewer);
  }

  @OptionalAuth()
  @Get('providers/:id')
  detail(@Param('id', ParseUUIDPipe) id: string, @MaybeUser() viewer?: AuthUser) {
    return this.services.detail(id, viewer);
  }

  @Public()
  @Get('providers/:id/reviews')
  reviews(@Param('id', ParseUUIDPipe) id: string, @Query() query: CursorQuery) {
    return this.services.reviews(id, query.cursor, query.limit);
  }

  @ApiBearerAuth()
  @Put('providers/:id/reviews/mine')
  review(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReviewDto) {
    return this.services.review(user, id, dto);
  }

  @ApiBearerAuth()
  @Delete('providers/:id/reviews/mine')
  async deleteReview(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.services.deleteReview(user, id);
    return { ok: true };
  }

  @ApiBearerAuth()
  @Post('providers/:id/contact')
  @HttpCode(200)
  contact(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.services.contact(user, id);
  }

  @ApiBearerAuth()
  @Get('me/provider')
  mine(@CurrentUser() user: AuthUser) {
    return this.services.mine(user);
  }

  @ApiBearerAuth()
  @Put('me/provider')
  upsert(@CurrentUser() user: AuthUser, @Body() dto: ProviderDto) {
    return this.services.upsert(user, dto);
  }

  @ApiBearerAuth()
  @Post('me/provider/status')
  @HttpCode(200)
  status(@CurrentUser() user: AuthUser, @Body() dto: ProviderStatusDto) {
    return this.services.setStatus(user, dto.status);
  }

  @ApiBearerAuth()
  @Put('me/provider/portfolio')
  portfolio(@CurrentUser() user: AuthUser, @Body() dto: PortfolioDto) {
    return this.services.setPortfolio(user, dto);
  }

  @ApiBearerAuth()
  @Post('me/provider/offerings')
  createOffering(@CurrentUser() user: AuthUser, @Body() dto: OfferingDto) {
    return this.services.createOffering(user, dto);
  }

  @ApiBearerAuth()
  @Patch('me/provider/offerings/:id')
  updateOffering(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: OfferingDto) {
    return this.services.updateOffering(user, id, dto);
  }

  @ApiBearerAuth()
  @Delete('me/provider/offerings/:id')
  async deleteOffering(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.services.deleteOffering(user, id);
    return { ok: true };
  }
}

@Module({ controllers: [ServicesController], providers: [ServicesService], exports: [ServicesService] })
export class ServicesModule {}
