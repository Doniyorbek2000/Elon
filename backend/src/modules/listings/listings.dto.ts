import { ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsBoolean,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

import { CursorQuery } from '../../common/pagination';

export const MAX_LISTING_PHOTOS = 12;

export class PlaceDto {
  @IsString()
  @MaxLength(64)
  regionId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  districtId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  localityId?: string | null;

  @IsOptional()
  @IsLatitude()
  lat?: number | null;

  @IsOptional()
  @IsLongitude()
  lng?: number | null;
}

export class MoneyDto {
  @IsInt()
  @Min(0)
  @Max(1_000_000_000_000)
  amount!: number;

  @IsIn(['uzs', 'usd'])
  currency!: string;
}

export class CreateListingDto {
  @IsString()
  @MaxLength(64)
  categoryId!: string;

  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(3, 70)
  title!: string;

  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(10, 3000)
  description!: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => MoneyDto)
  price?: MoneyDto | null;

  @IsOptional()
  @IsBoolean()
  negotiable?: boolean;

  @IsOptional()
  @IsIn(['new', 'used'])
  condition?: string | null;

  @IsOptional()
  @IsObject()
  attributes?: Record<string, unknown>;

  @ValidateNested()
  @Type(() => PlaceDto)
  place!: PlaceDto;

  @IsUUID('all', { each: true })
  @ArrayMaxSize(MAX_LISTING_PHOTOS)
  mediaIds!: string[];

  @ApiPropertyOptional({ description: 'Publish immediately (default true); false keeps a draft' })
  @IsOptional()
  @IsBoolean()
  publish?: boolean;
}

export class UpdateListingDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  categoryId?: string;

  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(3, 70)
  title?: string;

  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(10, 3000)
  description?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => MoneyDto)
  price?: MoneyDto | null;

  @IsOptional()
  @IsBoolean()
  negotiable?: boolean;

  @IsOptional()
  @IsIn(['new', 'used'])
  condition?: string | null;

  @IsOptional()
  @IsObject()
  attributes?: Record<string, unknown>;

  @IsOptional()
  @ValidateNested()
  @Type(() => PlaceDto)
  place?: PlaceDto;

  @IsOptional()
  @IsUUID('all', { each: true })
  @ArrayMaxSize(MAX_LISTING_PHOTOS)
  mediaIds?: string[];
}

export class ChangeStatusDto {
  @IsIn(['active', 'reserved', 'sold', 'archived'])
  status!: string;
}

export const LISTING_SORTS = ['newest', 'priceAsc', 'priceDesc', 'popular', 'nearest'] as const;
export type ListingSort = (typeof LISTING_SORTS)[number];

export class FeedQuery extends CursorQuery {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  region?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  district?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  locality?: string;

  @IsOptional()
  @Type(() => Number)
  @IsIn([1, 5, 10, 25, 50])
  radius?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  lat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  lng?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  priceMin?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  priceMax?: number;

  @IsOptional()
  @IsIn(['new', 'used'])
  condition?: string;

  @IsOptional()
  @IsUUID()
  seller?: string;

  @IsOptional()
  @IsIn(LISTING_SORTS)
  sort?: ListingSort;
}

export class MyListingsQuery extends CursorQuery {
  @IsOptional()
  @IsIn(['draft', 'pendingReview', 'active', 'reserved', 'sold', 'expired', 'rejected', 'archived'])
  status?: string;
}

export class RejectDto {
  @IsString()
  @Length(3, 300)
  reason!: string;
}
