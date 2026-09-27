import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsBoolean,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Length,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

import { CursorQuery } from '../../common/pagination';
import { PlaceDto } from '../listings/listings.dto';

const trim = ({ value }: { value: unknown }) => (typeof value === 'string' ? value.trim() : value);

export const EMPLOYMENT_TYPES = ['fullTime', 'partTime', 'temporary', 'internship'];
export const WORK_FORMATS = ['onSite', 'remote', 'hybrid'];
export const EXPERIENCE_LEVELS = ['none', 'upTo1', 'oneTo3', 'threePlus'];

export class JobInputDto {
  @Transform(trim)
  @IsString()
  @Length(3, 100)
  title!: string;

  @Transform(trim)
  @IsString()
  @Length(2, 100)
  companyName!: string;

  @Transform(trim)
  @IsString()
  @Length(20, 5000)
  description!: string;

  @IsOptional()
  @IsString({ each: true })
  @MaxLength(200, { each: true })
  @ArrayMaxSize(20)
  requirements?: string[];

  @IsOptional()
  @IsString({ each: true })
  @MaxLength(200, { each: true })
  @ArrayMaxSize(20)
  responsibilities?: string[];

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(1_000_000_000)
  salaryMin?: number | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(1_000_000_000)
  salaryMax?: number | null;

  @IsOptional()
  @IsIn(['uzs', 'usd'])
  salaryCurrency?: string;

  @IsOptional()
  @IsBoolean()
  salaryNegotiable?: boolean;

  @IsIn(EMPLOYMENT_TYPES)
  employmentType!: string;

  @IsOptional()
  @IsIn(WORK_FORMATS)
  workFormat?: string;

  @IsOptional()
  @IsIn(EXPERIENCE_LEVELS)
  experience?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  workSchedule?: string;

  @IsOptional()
  @IsIn(['inApp', 'phone', 'both'])
  applicationMode?: string;

  @ValidateNested()
  @Type(() => PlaceDto)
  place!: PlaceDto;

  @IsOptional()
  @IsBoolean()
  publish?: boolean;
}

export class JobStatusDto {
  @IsIn(['active', 'paused', 'filled', 'archived'])
  status!: string;
}

export class JobSearchQuery extends CursorQuery {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  q?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  region?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  district?: string;

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

  /** Comma-separated employment types. */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  types?: string;

  @IsOptional()
  @IsIn(EXPERIENCE_LEVELS)
  experience?: string;

  @IsOptional()
  @IsIn(WORK_FORMATS)
  workFormat?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  salaryMin?: number;

  @IsOptional()
  @IsIn(['newest', 'salary'])
  sort?: string;
}

export class MyJobsQuery extends CursorQuery {
  @IsOptional()
  @IsIn(['draft', 'active', 'paused', 'filled', 'expired', 'rejected', 'archived'])
  status?: string;
}

export class ApplyDto {
  @IsOptional()
  @Transform(trim)
  @IsString()
  @MaxLength(2000)
  coverLetter?: string;
}

export class ApplicationStatusDto {
  @IsIn(['viewed', 'shortlisted', 'rejected', 'accepted'])
  status!: string;
}

export class ApplicantsQuery extends CursorQuery {
  @IsOptional()
  @IsIn(['submitted', 'viewed', 'shortlisted', 'rejected', 'accepted', 'withdrawn'])
  status?: string;
}
