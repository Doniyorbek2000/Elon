import { Transform, Type } from 'class-transformer';
import {
  IsDate,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  IsUrl,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

import { CursorQuery } from '../../common/pagination';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export class BusinessDto {
  @Transform(trim) @IsString() @Length(2, 80) name!: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsString() @MaxLength(64) categoryId?: string;
  @IsString() @MaxLength(64) regionId!: string;
  @IsOptional() @IsString() @MaxLength(64) districtId?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) address?: string;
  @IsOptional() @IsString() @Matches(/^\+?[0-9 ()-]{9,20}$/) phone?: string;
  @IsOptional() @IsUrl({ protocols: ['https'], require_protocol: true }) website?: string;
  @IsOptional() @IsString() @Matches(/^@?[A-Za-z0-9_]{5,32}$/) telegram?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) openingHours?: string;
  @IsOptional() @IsUUID() logoId?: string;
}

export class UpdateBusinessDto {
  @IsOptional() @Transform(trim) @IsString() @Length(2, 80) name?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(2000) description?: string;
  @IsOptional() @IsString() @MaxLength(64) categoryId?: string;
  @IsOptional() @IsString() @MaxLength(64) regionId?: string;
  @IsOptional() @IsString() @MaxLength(64) districtId?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) address?: string;
  @IsOptional() @IsString() @Matches(/^\+?[0-9 ()-]{9,20}$/) phone?: string;
  @IsOptional() @IsUrl({ protocols: ['https'], require_protocol: true }) website?: string;
  @IsOptional() @IsString() @Matches(/^@?[A-Za-z0-9_]{5,32}$/) telegram?: string;
  @IsOptional() @Transform(trim) @IsString() @MaxLength(200) openingHours?: string;
  @IsOptional() @IsUUID() logoId?: string;
}

export class AddMemberDto {
  @IsString() @MaxLength(32) phone!: string;
}

export class StorefrontListingsQuery extends CursorQuery {}

export class StatsQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(90) days?: number;
  @IsOptional() @Type(() => Date) @IsDate() from?: Date;
  @IsOptional() @Type(() => Date) @IsDate() to?: Date;
}
