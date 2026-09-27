import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ListingStatus, MediaPurpose, MediaStatus } from '@prisma/client';
import sharp, { Metadata } from 'sharp';

import { env } from '../../config/env';
import { AuthUser } from '../../common/auth.decorators';
import { AppError } from '../../common/errors';
import { mediaSelect, presentMedia } from '../../common/presenters';
import { PrismaService } from '../../infra/prisma.service';
import { QueueService } from '../../infra/queues';
import { RateLimiterService } from '../../infra/rate-limiter.service';
import { StorageService } from '../../infra/storage.service';

/** Formats accepted after sniffing the actual bytes (client MIME is ignored). */
const ALLOWED_FORMATS: Record<string, string> = {
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  heif: 'image/heif',
};

const MAX_PIXELS = 50_000_000;

export type Variant = 'thumbnail' | 'feed' | 'detail';

export const RENDITIONS: Array<{
  variant: Variant;
  column: 'thumbKey' | 'feedKey' | 'detailKey';
  width: number;
}> = [
  { variant: 'thumbnail', column: 'thumbKey', width: 240 },
  { variant: 'feed', column: 'feedKey', width: 480 },
  { variant: 'detail', column: 'detailKey', width: 1080 },
];

@Injectable()
export class MediaService {
  private readonly logger = new Logger(MediaService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly queues: QueueService,
    private readonly limiter: RateLimiterService,
  ) {}

  async upload(ownerId: string, purpose: MediaPurpose, file: Express.Multer.File | undefined) {
    if (!file?.buffer?.length) throw AppError.validation('File is required', { field: 'file' });
    if (file.size > env().MEDIA_MAX_UPLOAD_BYTES) {
      throw new AppError('PAYLOAD_TOO_LARGE', 'File is too large', HttpStatus.PAYLOAD_TOO_LARGE);
    }
    await this.limiter.consume(`upload:${ownerId}`, 120, 3600);

    let metadata: Metadata;
    try {
      metadata = await sharp(file.buffer, { limitInputPixels: MAX_PIXELS }).metadata();
    } catch {
      throw new AppError('UNSUPPORTED_MEDIA', 'Not a supported image', HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    }
    const mimeType = metadata.format ? ALLOWED_FORMATS[metadata.format] : undefined;
    if (!mimeType)
      throw new AppError(
        'UNSUPPORTED_MEDIA',
        'Only JPEG, PNG, WebP or HEIF images',
        HttpStatus.UNSUPPORTED_MEDIA_TYPE,
      );

    const media = await this.prisma.media.create({
      data: {
        ownerId,
        purpose,
        status: MediaStatus.PROCESSING,
        mimeType,
        sizeBytes: file.size,
        width: metadata.width,
        height: metadata.height,
        originalKey: 'pending',
      },
    });
    const originalKey = `originals/${ownerId}/${media.id}`;
    try {
      await this.storage.put(originalKey, file.buffer, mimeType, 'private, no-store');
    } catch (error) {
      await this.prisma.media.delete({ where: { id: media.id } });
      this.logger.error({ err: error, mediaId: media.id }, 'Storage write failed');
      throw new AppError(
        'SERVICE_UNAVAILABLE',
        'Storage is temporarily unavailable',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    const saved = await this.prisma.media.update({
      where: { id: media.id },
      data: { originalKey },
      select: mediaSelect,
    });
    await this.queues.processMedia({ mediaId: media.id });
    return presentMedia(saved);
  }

  /**
   * Worker: auto-orients, strips metadata (EXIF/GPS is dropped by default),
   * renders WebP renditions. Idempotent: re-running overwrites the same keys.
   */
  async process(mediaId: string): Promise<void> {
    const media = await this.prisma.media.findUnique({ where: { id: mediaId } });
    if (!media || media.deletedAt || media.status === MediaStatus.READY) return;
    const original = await this.storage.getBuffer(media.originalKey);
    const oriented = await sharp(original, { limitInputPixels: MAX_PIXELS })
      .rotate()
      .toBuffer({ resolveWithObject: true });

    const keys: Partial<Record<'thumbKey' | 'feedKey' | 'detailKey', string>> = {};
    for (const rendition of RENDITIONS) {
      const square = rendition.variant === 'thumbnail' && media.purpose === MediaPurpose.AVATAR;
      const output = await sharp(oriented.data)
        .resize({
          width: rendition.width,
          height: square ? rendition.width : undefined,
          fit: square ? 'cover' : 'inside',
          withoutEnlargement: true,
        })
        .webp({ quality: rendition.variant === 'detail' ? 82 : 76 })
        .toBuffer();
      const key = `media/${media.id}/${rendition.variant}.webp`;
      const cache =
        media.purpose === MediaPurpose.CHAT
          ? 'private, max-age=86400'
          : 'public, max-age=31536000, immutable';
      await this.storage.put(key, output, 'image/webp', cache);
      keys[rendition.column] = key;
    }
    await this.prisma.media.update({
      where: { id: media.id },
      data: {
        ...keys,
        status: MediaStatus.READY,
        width: oriented.info.width,
        height: oriented.info.height,
        failureReason: null,
      },
    });
  }

  async markFailed(mediaId: string, reason: string): Promise<void> {
    await this.prisma.media.updateMany({
      where: { id: mediaId, status: MediaStatus.PROCESSING },
      data: { status: MediaStatus.FAILED, failureReason: reason.slice(0, 300) },
    });
  }

  async retry(ownerId: string, id: string) {
    const media = await this.prisma.media.findFirst({ where: { id, ownerId, deletedAt: null } });
    if (!media) throw AppError.notFound('Media');
    if (media.status !== MediaStatus.FAILED)
      throw AppError.invalidState('Only failed uploads can be retried');
    await this.limiter.consume(`upload:retry:${ownerId}`, 30, 3600);
    const updated = await this.prisma.media.update({
      where: { id },
      data: { status: MediaStatus.PROCESSING, failureReason: null },
    });
    await this.queues.processMedia({ mediaId: id }, `retry:${Date.now()}`);
    return presentMedia(updated);
  }

  async get(id: string, viewer?: AuthUser) {
    const media = await this.prisma.media.findFirst({ where: { id, deletedAt: null } });
    if (!media) throw AppError.notFound('Media');
    await this.assertReadable(media, viewer);
    return {
      ...presentMedia(media),
      purpose: media.purpose.toLowerCase(),
      failureReason: media.failureReason,
    };
  }

  async open(id: string, variant: Variant, viewer?: AuthUser) {
    const media = await this.prisma.media.findFirst({ where: { id, deletedAt: null } });
    if (!media || media.status !== MediaStatus.READY) throw AppError.notFound('Media');
    await this.assertReadable(media, viewer);
    const key = RENDITIONS.find((r) => r.variant === variant)!.column;
    const objectKey = media[key];
    if (!objectKey) throw AppError.notFound('Media');
    const object = await this.storage.getStream(objectKey);
    return { ...object, isPrivate: media.purpose === MediaPurpose.CHAT };
  }

  /** Chat attachments are visible only to conversation participants (and the uploader). */
  private async assertReadable(
    media: { id: string; purpose: MediaPurpose; ownerId: string },
    viewer?: AuthUser,
  ) {
    if (media.purpose !== MediaPurpose.CHAT) return;
    if (!viewer) throw AppError.unauthenticated();
    if (viewer.userId === media.ownerId) return;
    const participant = await this.prisma.conversationParticipant.findFirst({
      where: {
        userId: viewer.userId,
        conversation: { messages: { some: { attachments: { some: { mediaId: media.id } } } } },
      },
      select: { userId: true },
    });
    if (!participant) throw AppError.notFound('Media');
  }

  async delete(ownerId: string, id: string): Promise<void> {
    const media = await this.prisma.media.findFirst({
      where: { id, deletedAt: null },
      include: { listingLinks: { include: { listing: { select: { status: true } } } } },
    });
    if (!media || media.ownerId !== ownerId) throw AppError.notFound('Media');
    const inUse = media.listingLinks.some(
      (l) => l.listing.status === ListingStatus.ACTIVE || l.listing.status === ListingStatus.PENDING_REVIEW,
    );
    if (inUse) throw AppError.invalidState('Remove the photo from the listing first');
    await this.prisma.media.update({
      where: { id },
      data: { deletedAt: new Date(), status: MediaStatus.DELETED },
    });
    await this.queues.cleanupMedia({
      keys: [media.originalKey, media.thumbKey, media.feedKey, media.detailKey].filter(
        (k): k is string => !!k,
      ),
    });
  }

  /**
   * Validates that media ids belong to the caller, have the right purpose and
   * haven't failed. Returns ids in the given order.
   */
  async assertOwned(ownerId: string, ids: string[], purposes: MediaPurpose[]): Promise<string[]> {
    const unique = [...new Set(ids)];
    if (unique.length !== ids.length) throw AppError.validation('Duplicate media ids', { field: 'mediaIds' });
    if (unique.length === 0) return [];
    const rows = await this.prisma.media.findMany({
      where: {
        id: { in: unique },
        ownerId,
        deletedAt: null,
        purpose: { in: purposes },
        status: { not: MediaStatus.FAILED },
      },
      select: { id: true },
    });
    if (rows.length !== unique.length)
      throw AppError.validation('Unknown or unusable media', { field: 'mediaIds' });
    return ids;
  }

  /** Orphans: uploads never attached to anything after 24 h. */
  async cleanupOrphans(): Promise<number> {
    const cutoff = new Date(Date.now() - 24 * 3600 * 1000);
    const orphans = await this.prisma.media.findMany({
      where: {
        createdAt: { lt: cutoff },
        deletedAt: null,
        purpose: {
          in: [MediaPurpose.LISTING, MediaPurpose.OFFERING, MediaPurpose.PORTFOLIO, MediaPurpose.CHAT],
        },
        listingLinks: { none: {} },
        attachmentLinks: { none: {} },
        portfolioLinks: { none: {} },
        offeringLinks: { none: {} },
      },
      take: 500,
    });
    for (const media of orphans) {
      await this.prisma.media.update({
        where: { id: media.id },
        data: { deletedAt: new Date(), status: MediaStatus.DELETED },
      });
      await this.queues.cleanupMedia({
        keys: [media.originalKey, media.thumbKey, media.feedKey, media.detailKey].filter(
          (k): k is string => !!k,
        ),
      });
    }
    return orphans.length;
  }
}
