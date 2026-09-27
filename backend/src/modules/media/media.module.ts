import {
  HttpCode,
  Body,
  Controller,
  Delete,
  Get,
  Global,
  Module,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { MediaPurpose } from '@prisma/client';
import { IsIn } from 'class-validator';
import type { Response } from 'express';
import { memoryStorage } from 'multer';

import { env } from '../../config/env';
import { AuthUser, CurrentUser, MaybeUser, OptionalAuth } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { MediaService, Variant } from './media.service';

class UploadDto {
  @IsIn(['listing', 'avatar', 'chat', 'portfolio', 'offering'])
  purpose!: string;
}

const VARIANTS: Variant[] = ['thumbnail', 'feed', 'detail'];

@ApiTags('media')
@Controller('media')
class MediaController {
  constructor(private readonly media: MediaService) {}

  @ApiBearerAuth()
  @ApiConsumes('multipart/form-data')
  @Post()
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: env().MEDIA_MAX_UPLOAD_BYTES, files: 1, fields: 5 },
    }),
  )
  upload(@CurrentUser() user: AuthUser, @Body() dto: UploadDto, @UploadedFile() file?: Express.Multer.File) {
    return this.media.upload(user.userId, dto.purpose.toUpperCase() as MediaPurpose, file);
  }

  @OptionalAuth()
  @Get(':id')
  get(@Param('id', ParseUUIDPipe) id: string, @MaybeUser() viewer?: AuthUser) {
    return this.media.get(id, viewer);
  }

  /**
   * Streams a rendition. In production a CDN (MEDIA_PUBLIC_BASE_URL) serves
   * public images directly and this endpoint handles only private ones.
   */
  @OptionalAuth()
  @Get(':id/:variant')
  async stream(
    @Param('id', ParseUUIDPipe) id: string,
    @Param('variant') variant: string,
    @Res() response: Response,
    @MaybeUser() viewer?: AuthUser,
  ) {
    if (!VARIANTS.includes(variant as Variant)) throw AppError.notFound('Variant');
    const object = await this.media.open(id, variant as Variant, viewer);
    response.setHeader('Content-Type', object.contentType ?? 'image/webp');
    if (object.contentLength) response.setHeader('Content-Length', String(object.contentLength));
    response.setHeader('Cache-Control', object.isPrivate ? 'private, max-age=3600' : 'public, max-age=31536000, immutable');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    object.stream.pipe(response);
  }

  /** Re-runs processing for a failed upload (client "retry" without re-uploading). */
  @ApiBearerAuth()
  @Post(':id/retry')
  @HttpCode(200)
  retry(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.media.retry(user.userId, id);
  }

  @ApiBearerAuth()
  @Delete(':id')
  async remove(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.media.delete(user.userId, id);
    return { ok: true };
  }
}

@Global()
@Module({ controllers: [MediaController], providers: [MediaService], exports: [MediaService] })
export class MediaModule {}
