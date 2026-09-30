import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
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
import { PlaceDto } from '../listings/listings.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class AreaDto {
  @IsString() @MaxLength(64) regionId!: string;
  @IsOptional() @IsString() @MaxLength(64) districtId?: string | null;
}

export class ProviderDto {
  @Transform(trim) @IsString() @Length(2, 80) displayName!: string;
  @Transform(trim) @IsString() @Length(2, 80) profession!: string;
  @Transform(trim) @IsString() @Length(20, 3000) description!: string;
  @IsOptional() @IsInt() @Min(0) @Max(70) experienceYears?: number;
  @IsString({ each: true }) @ArrayMinSize(1) @ArrayMaxSize(5) categoryIds!: string[];
  @ValidateNested() @Type(() => PlaceDto) place!: PlaceDto;
  @IsOptional() @ValidateNested({ each: true }) @Type(() => AreaDto) @ArrayMaxSize(20) areas?: AreaDto[];
  @IsOptional() @IsIn(['available', 'busy', 'away']) availability?: string;
}

export class ProviderStatusDto {
  @IsIn(['active', 'paused']) status!: string;
}

export class OfferingDto {
  @IsString() @MaxLength(64) categoryId!: string;
  @Transform(trim) @IsString() @Length(3, 100) title!: string;
  @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @IsIn(['fixed', 'from', 'hourly', 'negotiable']) pricingType!: string;
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000_000) priceFrom?: number | null;
  @IsOptional() @IsInt() @Min(0) @Max(1_000_000_000) priceTo?: number | null;
  @IsOptional() @IsIn(['uzs', 'usd']) currency?: string;
  @IsOptional() @IsString() @MaxLength(40) priceUnit?: string;
  @IsOptional() @IsIn(['active', 'paused', 'archived']) status?: string;
  @IsOptional() @IsUUID('all', { each: true }) @ArrayMaxSize(10) mediaIds?: string[];
}

export class PortfolioDto {
  @IsUUID('all', { each: true }) @ArrayMaxSize(30) mediaIds!: string[];
}

export class ReviewDto {
  @IsInt() @Min(1) @Max(5) rating!: number;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(1000) text?: string;
}

export class ProviderSearchQuery extends CursorQuery {
  @IsOptional() @IsString() @MaxLength(100) q?: string;
  @IsOptional() @IsString() @MaxLength(64) category?: string;
  @IsOptional() @IsString() @MaxLength(64) region?: string;
  @IsOptional() @IsString() @MaxLength(64) district?: string;
  @IsOptional() @Type(() => Number) @IsIn([1, 5, 10, 25, 50]) radius?: number;
  @IsOptional() @Type(() => Number) @IsLatitude() lat?: number;
  @IsOptional() @Type(() => Number) @IsLongitude() lng?: number;
  @IsOptional() @IsIn(['all', 'online', 'topRated']) filter?: string;
  @IsOptional() @IsIn(['rating', 'newest', 'nearest']) sort?: string;
}
