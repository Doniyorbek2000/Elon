import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Module,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  Req,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';

import { AuthUser, CurrentUser, MaybeUser, OptionalAuth } from '../../common/auth.decorators';
import { JobInputDto, JobSearchQuery, JobStatusDto, MyJobsQuery } from './jobs.dto';
import { JobsService } from './jobs.service';

@ApiTags('jobs')
@Controller()
class JobsController {
  constructor(private readonly jobs: JobsService) {}

  @OptionalAuth()
  @Get('jobs')
  search(@Query() query: JobSearchQuery, @MaybeUser() viewer?: AuthUser) {
    return this.jobs.search(query, viewer);
  }

  @OptionalAuth()
  @Get('jobs/:id')
  detail(@Param('id', ParseUUIDPipe) id: string, @Req() request: Request, @MaybeUser() viewer?: AuthUser) {
    return this.jobs.detail(id, viewer, viewer?.userId ?? request.ip);
  }

  @ApiBearerAuth()
  @Post('jobs')
  create(@CurrentUser() user: AuthUser, @Body() dto: JobInputDto) {
    return this.jobs.create(user, dto);
  }

  @ApiBearerAuth()
  @Put('jobs/:id')
  update(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: JobInputDto) {
    return this.jobs.update(user, id, dto);
  }

  @ApiBearerAuth()
  @Post('jobs/:id/status')
  @HttpCode(200)
  status(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: JobStatusDto) {
    return this.jobs.changeStatus(user, id, dto.status);
  }

  @ApiBearerAuth()
  @Delete('jobs/:id')
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.jobs.remove(user, id);
    return { ok: true };
  }

  @ApiBearerAuth()
  @Post('jobs/:id/contact')
  @HttpCode(200)
  contact(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.jobs.contact(user, id);
  }

  @ApiBearerAuth()
  @Get('me/jobs')
  mine(@CurrentUser() user: AuthUser, @Query() query: MyJobsQuery) {
    return this.jobs.mine(user.userId, query);
  }
}

@Module({ controllers: [JobsController], providers: [JobsService], exports: [JobsService] })
export class JobsModule {}
