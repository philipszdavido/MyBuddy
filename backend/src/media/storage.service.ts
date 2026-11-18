import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Readable } from 'node:stream';
import type { Env } from '../config/env';

export interface HeadResult {
  sizeBytes: number;
  contentType?: string;
}

/**
 * Cloudflare R2 through the S3 API. Credentials stay on the server; clients only ever receive
 * short-lived presigned URLs for one exact object key.
 */
@Injectable()
export class StorageService {
  private readonly client: S3Client;
  readonly bucket: string;
  private readonly publicBase?: string;

  constructor(config: ConfigService<Env, true>) {
    const accountId = config.get('R2_ACCOUNT_ID', { infer: true });
    const endpoint = config.get('R2_ENDPOINT', { infer: true }) ?? (accountId ? `https://${accountId}.r2.cloudflarestorage.com` : undefined);
    this.bucket = config.get('R2_BUCKET_NAME', { infer: true }) ?? 'mybuddy-dev';
    this.publicBase = config.get('R2_PUBLIC_URL', { infer: true })?.replace(/\/+$/, '');
    this.client = new S3Client({
      region: 'auto',
      endpoint,
      forcePathStyle: !!config.get('R2_ENDPOINT', { infer: true }), // MinIO / custom endpoints
      credentials: {
        accessKeyId: config.get('R2_ACCESS_KEY_ID', { infer: true }) ?? '',
        secretAccessKey: config.get('R2_SECRET_ACCESS_KEY', { infer: true }) ?? '',
      },
    });
  }

  /**
   * Presigned PUT bound to the key, content type and exact content length: R2 rejects an upload
   * whose Content-Type or Content-Length differs from what was signed.
   */
  presignPut(key: string, contentType: string, contentLength: number, expiresInSeconds = 900): Promise<string> {
    return getSignedUrl(
      this.client,
      new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: contentType, ContentLength: contentLength }),
      { expiresIn: expiresInSeconds, signableHeaders: new Set(['content-type', 'content-length']) },
    );
  }

  presignGet(key: string, expiresInSeconds = 3600): Promise<string> {
    return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: expiresInSeconds });
  }

  /** Public CDN URL (custom domain on the bucket) for keys that are safe to serve publicly. */
  publicUrl(key: string): string | undefined {
    return this.publicBase ? `${this.publicBase}/${key}` : undefined;
  }

  async head(key: string): Promise<HeadResult | null> {
    try {
      const res = await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return { sizeBytes: Number(res.ContentLength ?? 0), contentType: res.ContentType };
    } catch (error) {
      const status = (error as { $metadata?: { httpStatusCode?: number } }).$metadata?.httpStatusCode;
      if (status === 404) return null;
      throw error;
    }
  }

  /** First `bytes` of the object (magic-byte sniffing without downloading the whole file). */
  async readHead(key: string, bytes = 4100): Promise<Buffer> {
    const res = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key, Range: `bytes=0-${bytes - 1}` }));
    return streamToBuffer(res.Body as Readable);
  }

  async download(key: string): Promise<Buffer> {
    const res = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return streamToBuffer(res.Body as Readable);
  }

  async put(key: string, body: Buffer, contentType: string, cacheControl = 'public, max-age=31536000, immutable'): Promise<void> {
    await this.client.send(new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: body, ContentType: contentType, CacheControl: cacheControl }));
  }

  async delete(key: string): Promise<void> {
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }

  async deleteMany(keys: string[]): Promise<void> {
    for (let i = 0; i < keys.length; i += 1000) {
      const chunk = keys.slice(i, i + 1000);
      if (chunk.length === 0) continue;
      await this.client.send(new DeleteObjectsCommand({ Bucket: this.bucket, Delete: { Objects: chunk.map((Key) => ({ Key })), Quiet: true } }));
    }
  }
}

async function streamToBuffer(stream: Readable): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of stream) chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : (chunk as Buffer));
  return Buffer.concat(chunks);
}
