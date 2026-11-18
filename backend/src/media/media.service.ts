import { InjectQueue } from '@nestjs/bullmq';
import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { MediaKind, MediaPurpose } from '@prisma/client';
import { Queue } from 'bullmq';
import { randomUUID } from 'node:crypto';
import { AppError } from '../common/errors/app-error';
import { PrismaService } from '../prisma/prisma.service';
import { ProcessMediaJob, Q } from '../queues/queues';
import { MediaPresenter, MediaView } from './media-presenter.service';
import { sniff, SniffedType } from './sniff';
import { StorageService } from './storage.service';

const MB = 1024 * 1024;
const IMAGE_TYPES: SniffedType[] = ['image/jpeg', 'image/png', 'image/webp'];
const VIDEO_TYPES: SniffedType[] = ['video/mp4', 'video/quicktime'];

/** What each purpose accepts, and how big it may be. */
export const MEDIA_RULES: Record<MediaPurpose, { kinds: MediaKind[]; maxImage: number; maxVideo: number }> = {
  AVATAR: { kinds: ['IMAGE'], maxImage: 10 * MB, maxVideo: 0 },
  COVER: { kinds: ['IMAGE'], maxImage: 15 * MB, maxVideo: 0 },
  POST: { kinds: ['IMAGE', 'VIDEO'], maxImage: 20 * MB, maxVideo: 300 * MB },
  MESSAGE: { kinds: ['IMAGE', 'VIDEO'], maxImage: 20 * MB, maxVideo: 200 * MB },
};
const MAX_PENDING_UPLOADS = 30;
const UPLOAD_URL_TTL_SECONDS = 15 * 60;

export interface UploadTicket {
  mediaId: string;
  uploadUrl: string;
  method: 'PUT';
  /** Headers the client must send with the PUT, exactly (they are part of the signature). */
  headers: Record<string, string>;
  expiresAt: string;
}

/**
 * Direct-to-R2 uploads:
 *  1. POST /media/upload-url — validates purpose/type/size, creates the asset (PENDING_UPLOAD) and returns a
 *     presigned PUT for a server-chosen key bound to that content type and length.
 *  2. Client PUTs the bytes straight to R2 (the API never proxies file data; upload progress is native).
 *  3. POST /media/complete — the server HEADs the object, checks the real size, sniffs the real format, then
 *     queues processing. Only processed variants are ever served; originals are never public.
 */
@Injectable()
export class MediaService {
  private readonly logger = new Logger(MediaService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly presenter: MediaPresenter,
    @InjectQueue(Q.media) private readonly imageQueue: Queue<ProcessMediaJob>,
    @InjectQueue(Q.video) private readonly videoQueue: Queue<ProcessMediaJob>,
  ) {}

  async createUpload(ownerId: string, purpose: MediaPurpose, mimeType: string, sizeBytes: number): Promise<UploadTicket> {
    const kind = kindOf(mimeType);
    if (!kind) {
      const hint = /heic|heif/i.test(mimeType) ? ' Convert HEIC photos to JPEG before uploading.' : '';
      throw new AppError('UNSUPPORTED_MEDIA', `Unsupported media type.${hint}`, HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    }
    const rules = MEDIA_RULES[purpose];
    if (!rules.kinds.includes(kind)) throw new AppError('UNSUPPORTED_MEDIA', `${kind.toLowerCase()} is not allowed here`, HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    const max = kind === 'IMAGE' ? rules.maxImage : rules.maxVideo;
    if (sizeBytes > max) throw new AppError('MEDIA_TOO_LARGE', `File is larger than ${Math.round(max / MB)} MB`, HttpStatus.PAYLOAD_TOO_LARGE, { maxBytes: max });

    const pending = await this.prisma.mediaAsset.count({ where: { ownerId, status: 'PENDING_UPLOAD', deletedAt: null } });
    if (pending >= MAX_PENDING_UPLOADS) throw new AppError('RATE_LIMITED', 'Too many unfinished uploads', HttpStatus.TOO_MANY_REQUESTS);

    const id = randomUUID();
    // Key is unguessable and server-chosen: u/{owner}/{asset}/original. Clients cannot pick paths.
    const objectKey = `u/${ownerId}/${id}/original`;
    await this.prisma.mediaAsset.create({
      data: { id, ownerId, kind, purpose, objectKey, mimeType, declaredBytes: BigInt(sizeBytes) },
    });
    const uploadUrl = await this.storage.presignPut(objectKey, mimeType, sizeBytes, UPLOAD_URL_TTL_SECONDS);
    return {
      mediaId: id,
      uploadUrl,
      method: 'PUT',
      headers: { 'Content-Type': mimeType, 'Content-Length': String(sizeBytes) },
      expiresAt: new Date(Date.now() + UPLOAD_URL_TTL_SECONDS * 1000).toISOString(),
    };
  }

  async complete(ownerId: string, mediaId: string): Promise<MediaView> {
    const asset = await this.prisma.mediaAsset.findFirst({ where: { id: mediaId, ownerId, deletedAt: null } });
    if (!asset) throw AppError.notFound('Media');
    if (asset.status !== 'PENDING_UPLOAD') return this.presenter.present(asset, 'private'); // idempotent

    const head = await this.storage.head(asset.objectKey);
    if (!head) throw AppError.conflict('The file has not been uploaded yet');
    const rules = MEDIA_RULES[asset.purpose];
    const max = asset.kind === 'IMAGE' ? rules.maxImage : rules.maxVideo;
    const reject = async (code: 'UNSUPPORTED_MEDIA' | 'MEDIA_TOO_LARGE', message: string, status: HttpStatus) => {
      await this.storage.delete(asset.objectKey).catch(() => undefined);
      await this.prisma.mediaAsset.update({ where: { id: asset.id }, data: { status: 'FAILED', error: message } });
      throw new AppError(code, message, status);
    };
    if (head.sizeBytes > max || head.sizeBytes !== Number(asset.declaredBytes)) {
      await reject('MEDIA_TOO_LARGE', 'Uploaded file size does not match the declared size', HttpStatus.PAYLOAD_TOO_LARGE);
    }
    const actual = sniff(await this.storage.readHead(asset.objectKey));
    if (!actual || kindOf(actual) !== asset.kind) {
      this.logger.warn(`rejected upload ${asset.id}: declared ${asset.mimeType}, sniffed ${actual ?? 'unknown'}`);
      await reject('UNSUPPORTED_MEDIA', 'File content does not match an allowed media type', HttpStatus.UNSUPPORTED_MEDIA_TYPE);
    }

    const updated = await this.prisma.mediaAsset.update({
      where: { id: asset.id },
      data: { status: 'PROCESSING', uploadedAt: new Date(), sizeBytes: BigInt(head.sizeBytes), mimeType: actual! },
    });
    const queue = asset.kind === 'IMAGE' ? this.imageQueue : this.videoQueue;
    await queue.add('process', { mediaId: asset.id }, { jobId: `m-${asset.id}`, attempts: asset.kind === 'VIDEO' ? 3 : 5 });
    return this.presenter.present(updated, 'private');
  }

  /** Owner-only status polling (processing progress, final URLs). */
  async get(ownerId: string, mediaId: string): Promise<MediaView> {
    const asset = await this.prisma.mediaAsset.findFirst({ where: { id: mediaId, ownerId, deletedAt: null } });
    if (!asset) throw AppError.notFound('Media');
    return this.presenter.present(asset, 'private');
  }

  /** Deletes an unattached asset. Attached media is removed with its post/message. */
  async remove(ownerId: string, mediaId: string): Promise<void> {
    const asset = await this.prisma.mediaAsset.findFirst({
      where: { id: mediaId, ownerId, deletedAt: null },
      include: { postMedia: { select: { post: { select: { deletedAt: true } } } }, attachment: true, avatarOf: true, coverOf: true },
    });
    if (!asset) throw AppError.notFound('Media');
    const inUse = (asset.postMedia && !asset.postMedia.post.deletedAt) || asset.attachment || asset.avatarOf || asset.coverOf;
    if (inUse) throw AppError.conflict('Media is in use; delete the post or message instead');
    // Objects are removed by the cleanup queue (batched, retried).
    await this.prisma.mediaAsset.update({ where: { id: asset.id }, data: { deletedAt: new Date() } });
  }
}

export function kindOf(mimeType: string): MediaKind | null {
  const m = mimeType.toLowerCase().split(';')[0].trim() as SniffedType;
  if (IMAGE_TYPES.includes(m)) return 'IMAGE';
  if (VIDEO_TYPES.includes(m)) return 'VIDEO';
  return null;
}
