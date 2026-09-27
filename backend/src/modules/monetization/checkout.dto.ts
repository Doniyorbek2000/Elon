import { Transform } from 'class-transformer';
import { IsIn, IsOptional, IsString, IsUUID, Length, Matches, MaxLength } from 'class-validator';

import { CursorQuery } from '../../common/pagination';

const trimUpper = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.trim().toUpperCase() : value;

/**
 * Checkout input. Note what is *absent*: price, amount, currency, status,
 * userId. The server derives all of them; unknown fields are rejected (422).
 */
export class CheckoutDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  productId?: string;

  @IsOptional()
  @IsUUID()
  planPriceId?: string;

  /** Listing / job / provider / ad campaign being promoted. */
  @IsOptional()
  @IsUUID()
  targetId?: string;

  @IsOptional()
  @Transform(trimUpper)
  @IsString()
  @Length(3, 32)
  couponCode?: string;

  @IsIn(['dev', 'payme', 'click', 'apple', 'google', 'credits', 'free'])
  provider!: string;

  @IsIn(['ios', 'android', 'web'])
  platform!: string;

  /** Client-generated; retries with the same key return the same purchase. */
  @IsString()
  @Matches(/^[A-Za-z0-9_-]{8,64}$/)
  idempotencyKey!: string;
}

export class QuoteDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  productId?: string;

  @IsOptional()
  @IsUUID()
  planPriceId?: string;

  @IsOptional()
  @IsUUID()
  targetId?: string;

  @IsOptional()
  @Transform(trimUpper)
  @IsString()
  @Length(3, 32)
  couponCode?: string;

  @IsIn(['ios', 'android', 'web'])
  platform!: string;
}

export class CatalogQuery {
  @IsIn(['listing', 'job', 'provider', 'business'])
  target!: string;

  @IsOptional()
  @IsUUID()
  targetId?: string;

  @IsOptional()
  @IsIn(['ios', 'android', 'web'])
  platform?: string;
}

export class PurchasesQuery extends CursorQuery {}
