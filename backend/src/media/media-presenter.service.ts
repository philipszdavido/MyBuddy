import { Injectable } from '@nestjs/common';
import type { MediaAsset } from '@prisma/client';
import { StorageService } from './storage.service';

export interface VariantInfo {
  key: string;
  width?: number;
  height?: number;
  mimeType?: string;
}

/** Shape stored in media_assets.variants by the processing jobs. */
export type MediaVariants = Partial<Record<'thumb' | 'medium' | 'large' | 'poster' | 'mp4_480' | 'mp4_720', VariantInfo>>;

export interface MediaView {
  id: string;
  kind: 'IMAGE' | 'VIDEO';
  status: 'PENDING_UPLOAD' | 'PROCESSING' | 'READY' | 'FAILED';
  width: number | null;
  height: number | null;
  durationMs: number | null;
  blurhash: string | null;
  /** Variant name -> URL. Empty until processing finished. */
  urls: Record<string, string>;
}

export type Visibility = 'public' | 'private';

/**
 * Turns stored assets into client URLs. Public content (avatars, covers, PUBLIC posts) is served from the
 * CDN domain; everything else (messages, followers/contacts-only posts) gets short-lived signed URLs, so
 * a leaked link stops working. Originals are never exposed.
 */
@Injectable()
export class MediaPresenter {
  constructor(private readonly storage: StorageService) {}

  async present(asset: Pick<MediaAsset, 'id' | 'kind' | 'status' | 'width' | 'height' | 'durationMs' | 'blurhash' | 'variants'>, visibility: Visibility): Promise<MediaView> {
    const variants = (asset.variants ?? {}) as MediaVariants;
    const urls: Record<string, string> = {};
    if (asset.status === 'READY') {
      for (const [name, variant] of Object.entries(variants)) {
        if (!variant?.key) continue;
        const url = visibility === 'public' ? this.storage.publicUrl(variant.key) : undefined;
        urls[name] = url ?? (await this.storage.presignGet(variant.key));
      }
    }
    return {
      id: asset.id,
      kind: asset.kind,
      status: asset.status,
      width: asset.width,
      height: asset.height,
      durationMs: asset.durationMs,
      blurhash: asset.blurhash,
      urls,
    };
  }

  /** Single best URL for small UI (avatars): medium, else thumb. */
  async avatarUrl(asset: Pick<MediaAsset, 'status' | 'variants'> | null | undefined): Promise<string | null> {
    if (!asset || asset.status !== 'READY') return null;
    const v = (asset.variants ?? {}) as MediaVariants;
    const key = v.medium?.key ?? v.thumb?.key;
    if (!key) return null;
    return this.storage.publicUrl(key) ?? (await this.storage.presignGet(key));
  }
}
