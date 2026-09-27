import { Transform } from 'class-transformer';
import { ArrayMaxSize, IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';

import { CursorQuery } from '../../common/pagination';

export class OpenConversationDto {
  /** What the chat is about; the other participant is derived from it server-side. */
  @IsIn(['listing', 'job', 'service', 'candidate'])
  contextType!: string;

  @IsUUID()
  contextId!: string;
}

export class SendMessageDto {
  @IsIn(['text', 'image', 'listingShare'])
  type!: string;

  @IsOptional()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @Length(1, 4000)
  text?: string;

  @IsOptional()
  @IsUUID('all', { each: true })
  @ArrayMaxSize(6)
  mediaIds?: string[];

  @IsOptional()
  @IsUUID()
  sharedListingId?: string;

  /** Client-generated id: retries of the same message are deduplicated. */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  clientId?: string;
}

export class MessagesQuery extends CursorQuery {}
