import {
  CreateBucketCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import type { Readable } from 'node:stream';

import { env } from '../config/env';

/**
 * S3-compatible object storage (SeaweedFS/MinIO locally; AWS S3, Cloudflare
 * R2 etc. in production — only S3_* variables change).
 */
@Injectable()
export class StorageService implements OnModuleInit {
  private readonly logger = new Logger(StorageService.name);
  private readonly client: S3Client;
  readonly bucket: string;

  constructor() {
    const config = env();
    this.bucket = config.S3_BUCKET;
    this.client = new S3Client({
      region: config.S3_REGION,
      endpoint: config.S3_ENDPOINT,
      forcePathStyle: config.S3_FORCE_PATH_STYLE,
      credentials: { accessKeyId: config.S3_ACCESS_KEY_ID, secretAccessKey: config.S3_SECRET_ACCESS_KEY },
    });
  }

  async onModuleInit(): Promise<void> {
    try {
      await this.client.send(new HeadBucketCommand({ Bucket: this.bucket }));
    } catch {
      if (env().NODE_ENV === 'production') {
        this.logger.warn(`Bucket ${this.bucket} is not reachable; uploads will fail until it exists`);
        return;
      }
      await this.client.send(new CreateBucketCommand({ Bucket: this.bucket })).catch((error: unknown) => {
        this.logger.warn({ err: error }, 'Could not create development bucket');
      });
    }
  }

  async put(key: string, body: Buffer, contentType: string, cacheControl = 'private, max-age=31536000, immutable') {
    await this.client.send(
      new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: body, ContentType: contentType, CacheControl: cacheControl }),
    );
  }

  async getBuffer(key: string): Promise<Buffer> {
    const result = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    const bytes = await result.Body?.transformToByteArray();
    if (!bytes) throw new Error(`Empty object ${key}`);
    return Buffer.from(bytes);
  }

  async getStream(key: string): Promise<{ stream: Readable; contentType?: string; contentLength?: number }> {
    const result = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return {
      stream: result.Body as Readable,
      contentType: result.ContentType,
      contentLength: result.ContentLength,
    };
  }

  async deleteMany(keys: string[]): Promise<void> {
    const objects = keys.filter(Boolean).map((Key) => ({ Key }));
    if (objects.length === 0) return;
    await this.client.send(new DeleteObjectsCommand({ Bucket: this.bucket, Delete: { Objects: objects, Quiet: true } }));
  }

  async ping(): Promise<boolean> {
    try {
      await this.client.send(new HeadBucketCommand({ Bucket: this.bucket }));
      return true;
    } catch {
      return false;
    }
  }
}
