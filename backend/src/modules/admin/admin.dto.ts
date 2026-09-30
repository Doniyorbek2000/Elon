import { IsIn } from 'class-validator';

export class VerificationDto {
  @IsIn(['none', 'pending', 'verified', 'rejected']) verification!: string;
}

export class BusinessStatusDto {
  @IsIn(['active', 'suspended']) status!: string;
}
