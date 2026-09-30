import { Body, Controller, Get, Module, Param, ParseUUIDPipe, Patch, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { BusinessStatus, BusinessVerification } from '@prisma/client';

import { AuthUser, CurrentUser, Roles } from '../../common/auth.decorators';
import { dbEnum } from '../../common/text';
import { PrismaService } from '../../infra/prisma.service';
import { BusinessService } from '../business/business.service';
import { BusinessStatusDto, VerificationDto } from './admin.dto';
import { AdminService } from './admin.service';

/** Business administration (ADMIN only). Every change is written to the audit log. */
@ApiTags('admin')
@ApiBearerAuth()
@Roles('ADMIN')
@Controller('admin')
class AdminController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly admin: AdminService,
    private readonly business: BusinessService,
  ) {}

  @Get('businesses')
  businesses(@Query('verification') verification?: string) {
    return this.prisma.business.findMany({
      where: verification ? { verification: dbEnum(verification) as BusinessVerification } : {},
      orderBy: { updatedAt: 'desc' },
      take: 100,
    });
  }

  @Patch('businesses/:id/verification')
  async verify(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: VerificationDto,
  ) {
    const result = await this.business.setVerification(id, dbEnum(dto.verification) as BusinessVerification);
    await this.admin.audit(user.userId, 'business.verification', 'Business', id, dto);
    return result;
  }

  @Patch('businesses/:id/status')
  async businessStatus(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: BusinessStatusDto,
  ) {
    const result = await this.prisma.business.update({
      where: { id },
      data: { status: dbEnum(dto.status) as BusinessStatus },
    });
    await this.admin.audit(user.userId, 'business.status', 'Business', id, dto);
    return result;
  }
}

@Module({ controllers: [AdminController], providers: [AdminService] })
export class AdminModule {}
