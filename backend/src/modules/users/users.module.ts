import { Body, Controller, Get, Injectable, Module, Param, ParseUUIDPipe, Patch } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { ListingStatus, MediaPurpose, MediaStatus, Prisma, UserStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

import { AuthUser, CurrentUser, OptionalAuth } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { presentMedia, presentUser, publicUserSelect, mediaSelect } from '../../common/presenters';
import { apiEnum } from '../../common/text';
import { LANGUAGES, Lang } from '../../common/i18n';
import { PresenceService } from '../../infra/presence.service';
import { PrismaService } from '../../infra/prisma.service';
import { LocationsService } from '../locations/locations.service';

export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Length(2, 60)
  displayName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  bio?: string;

  /** Media id of a READY avatar upload owned by the caller; null clears it. */
  @IsOptional()
  @IsUUID()
  avatarId?: string | null;

  @IsOptional()
  @IsBoolean()
  showPhone?: boolean;

  @IsOptional()
  @IsBoolean()
  messagePreviews?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  preferredRegionId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  preferredDistrictId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  preferredLocalityId?: string | null;

  @IsOptional()
  @IsIn(LANGUAGES)
  language?: Lang;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @IsIn([1, 5, 10, 25, 50])
  @Min(1)
  @Max(50)
  preferredRadiusKm?: number | null;
}

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly locations: LocationsService,
    private readonly presence: PresenceService,
  ) {}

  async me(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: {
        profile: {
          include: {
            avatar: { select: mediaSelect },
            preferredRegion: true,
            preferredDistrict: true,
            preferredLocality: true,
          },
        },
      },
    });
    const profile = user.profile!;
    return {
      id: user.id,
      displayId: user.id.replace(/-/g, '').slice(0, 8).toUpperCase(),
      phone: user.phone,
      name: profile.displayName,
      bio: profile.bio,
      avatar: profile.avatar ? presentMedia(profile.avatar) : null,
      verification: apiEnum(profile.verification),
      accountType: apiEnum(profile.accountType),
      role: apiEnum(user.role),
      memberSince: user.createdAt,
      settings: {
        showPhone: profile.showPhone,
        messagePreviews: profile.messagePreviews,
        language: profile.language,
      },
      preferredLocation: profile.preferredRegion
        ? {
            regionId: profile.preferredRegion.id,
            regionName: profile.preferredRegion.name,
            districtId: profile.preferredDistrict?.id ?? null,
            districtName: profile.preferredDistrict?.name ?? null,
            localityId: profile.preferredLocality?.id ?? null,
            localityName: profile.preferredLocality?.name ?? null,
            radiusKm: profile.preferredRadiusKm,
          }
        : null,
    };
  }

  async update(userId: string, dto: UpdateMeDto) {
    const data: Prisma.ProfileUncheckedUpdateInput = {
      displayName: dto.displayName?.trim(),
      bio: dto.bio?.trim(),
      showPhone: dto.showPhone,
      messagePreviews: dto.messagePreviews,
      language: dto.language,
    };
    if (dto.avatarId !== undefined) {
      if (dto.avatarId) {
        const media = await this.prisma.media.findFirst({
          where: { id: dto.avatarId, ownerId: userId, purpose: MediaPurpose.AVATAR, deletedAt: null },
        });
        if (!media || media.status === MediaStatus.FAILED)
          throw AppError.validation('Invalid avatar', { field: 'avatarId' });
      }
      data.avatarId = dto.avatarId;
    }
    if (dto.preferredRegionId) {
      const place = await this.locations.resolvePlace({
        regionId: dto.preferredRegionId,
        districtId: dto.preferredDistrictId,
        localityId: dto.preferredLocalityId,
      });
      data.preferredRegionId = place.regionId;
      data.preferredDistrictId = place.districtId;
      data.preferredLocalityId = place.localityId;
    }
    if (dto.preferredRadiusKm !== undefined) data.preferredRadiusKm = dto.preferredRadiusKm;
    await this.prisma.profile.update({ where: { userId }, data });
    return this.me(userId);
  }

  async publicProfile(userId: string) {
    const user = await this.prisma.user.findFirst({
      where: { id: userId, status: UserStatus.ACTIVE, deletedAt: null },
      select: publicUserSelect,
    });
    if (!user) throw AppError.notFound('User');
    const [activeListings, isOnline] = await Promise.all([
      this.prisma.listing.count({
        where: { sellerId: userId, status: ListingStatus.ACTIVE, deletedAt: null },
      }),
      this.presence.isOnline(userId),
    ]);
    return presentUser(user, { activeListings, isOnline });
  }
}

@ApiTags('users')
@ApiBearerAuth()
@Controller()
class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.users.me(user.userId);
  }

  @Patch('me')
  update(@CurrentUser() user: AuthUser, @Body() dto: UpdateMeDto) {
    return this.users.update(user.userId, dto);
  }

  @OptionalAuth()
  @Get('users/:id')
  publicProfile(@Param('id', ParseUUIDPipe) id: string) {
    return this.users.publicProfile(id);
  }
}

@Module({ controllers: [UsersController], providers: [UsersService], exports: [UsersService] })
export class UsersModule {}
