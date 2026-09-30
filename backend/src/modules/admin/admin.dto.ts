import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDate,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

import { CursorQuery } from '../../common/pagination';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);
/** Money arrives as a decimal string of minor units (BigInt-safe, no floats). */
const MINOR = /^[0-9]{1,15}$/;

export class FlagDto {
  @IsBoolean() enabled!: boolean;
  @IsOptional() @IsString() @MaxLength(200) description?: string;
}

export class SettingDto {
  @IsObject() value!: Record<string, unknown>;
}

export class ProductDto {
  @Matches(/^[a-z0-9_]{3,64}$/) id!: string;
  @IsIn([
    'listingTop',
    'listingVip',
    'listingBump',
    'listingFeatured',
    'jobTop',
    'jobFeatured',
    'jobUrgent',
    'providerTop',
    'providerFeatured',
    'adCampaign',
  ])
  kind!: string;
  @IsOptional() @IsIn(['none', 'home', 'category', 'region']) placement?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(365) durationDays?: number;
  @Transform(trim) @IsString() @Length(2, 80) title!: string;
  @Transform(trim) @IsString() @Length(2, 300) description!: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) creditCost?: number;
  @IsOptional() @Type(() => Number) @IsInt() sortOrder?: number;
}

export class UpdateProductDto {
  @IsOptional() @Transform(trim) @IsString() @Length(2, 80) title?: string;
  @IsOptional() @Transform(trim) @IsString() @Length(2, 300) description?: string;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) creditCost?: number | null;
  @IsOptional() @Type(() => Number) @IsInt() sortOrder?: number;
}

export class PriceDto {
  @Matches(MINOR) amountMinor!: string;
  @IsIn(['uzs', 'usd']) currency!: string;
  /** Future date schedules a price change; defaults to now. */
  @IsOptional() @Type(() => Date) @IsDate() validFrom?: Date;
  @IsOptional() @IsIn(['month', 'year']) period?: string;
}

export class UpdatePlanDto {
  @IsOptional() @Transform(trim) @IsString() @Length(2, 60) title?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(500) description?: string;
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) activeListingLimit?: number | null;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) monthlyListingLimit?: number | null;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) photoLimit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) activeJobLimit?: number | null;
  @IsOptional() @IsBoolean() storefront?: boolean;
  @IsOptional() @IsBoolean() businessBadge?: boolean;
  @IsOptional() @IsIn(['basic', 'advanced']) analytics?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(50) maxManagers?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(1000) monthlyPromotionCredits?: number;
  @IsOptional() @IsBoolean() prioritySupport?: boolean;
}

export class CouponDto {
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim().toUpperCase() : value,
  )
  @Matches(/^[A-Z0-9_-]{3,32}$/)
  code!: string;
  @IsOptional() @IsString() @MaxLength(200) description?: string;
  @IsIn(['percent', 'fixed']) discountType!: string;
  @Matches(MINOR) value!: string;
  @IsOptional() @IsIn(['uzs', 'usd']) currency?: string;
  @Type(() => Date) @IsDate() validFrom!: Date;
  @IsOptional() @Type(() => Date) @IsDate() validUntil?: Date;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) maxRedemptions?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) perUserLimit?: number;
  @IsOptional() @IsArray() @ArrayMaxSize(50) @IsString({ each: true }) productIds?: string[];
  @IsOptional() @IsArray() @ArrayMaxSize(10) @IsString({ each: true }) planIds?: string[];
}

export class UpdateCouponDto {
  @IsOptional() @IsBoolean() active?: boolean;
  @IsOptional() @Type(() => Date) @IsDate() validUntil?: Date;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) maxRedemptions?: number;
}

export class VerificationDto {
  @IsIn(['none', 'pending', 'verified', 'rejected']) verification!: string;
}

export class BusinessStatusDto {
  @IsIn(['active', 'suspended']) status!: string;
}

export class PaymentsQuery extends CursorQuery {
  @IsOptional()
  @IsIn(['created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded', 'partiallyRefunded'])
  status?: string;
  @IsOptional() @IsIn(['dev', 'payme', 'click', 'apple', 'google', 'credits', 'free']) provider?: string;
  @IsOptional() @Type(() => Boolean) @IsBoolean() needsReview?: boolean;
}

export class RefundDto {
  @IsOptional() @Matches(MINOR) amountMinor?: string;
  @Transform(trim) @IsString() @Length(5, 500) reason!: string;
  /** Override the product's refund policy (reason is recorded in the audit log). */
  @IsOptional() @IsBoolean() overridePolicy?: boolean;
}

export class ReasonDto {
  @Transform(trim) @IsString() @Length(3, 500) reason!: string;
}

export class CreditAdjustDto {
  @Type(() => Number) @IsInt() @Min(-1000) @Max(1000) amount!: number;
  @Transform(trim) @IsString() @Length(5, 300) reason!: string;
}

export class RevenueQuery {
  @Type(() => Date) @IsDate() from!: Date;
  @Type(() => Date) @IsDate() to!: Date;
  @IsOptional() @IsIn(['day', 'week', 'month']) groupBy?: 'day' | 'week' | 'month';
}

export class StoreProductDto {
  @IsIn(['APPLE', 'GOOGLE']) provider!: 'APPLE' | 'GOOGLE';
  @IsString() @Length(3, 200) storeProductId!: string;
  /** Exactly one of these two. */
  @IsOptional() @IsString() @Length(3, 64) productId?: string;
  @IsOptional() @IsString() @Length(36, 36) planPriceId?: string;
}
