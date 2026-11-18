import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { MediaVariants } from './media-presenter.service';
import { StorageService } from './storage.service';

const BATCH = 200;

/**
 * Orphaned-upload cleanup, run periodically by the cleanup queue:
 *  - uploads never completed (PENDING_UPLOAD > 24h) and failed uploads (> 24h)
 *  - assets soft-deleted with their post/message/account
 *  - processed post/message media never attached to anything after 7 days
 *  - replaced avatars/covers after 7 days
 * Objects are deleted from R2 first, then the rows, so a crash in between only leaves rows to retry.
 */
@Injectable()
export class MediaCleanup {
  private readonly logger = new Logger(MediaCleanup.name);

  constructor(private readonly prisma: PrismaService, private readonly storage: StorageService) {}

  async sweep(now = new Date()): Promise<{ deleted: number }> {
    const day = new Date(now.getTime() - 24 * 3600_000);
    const week = new Date(now.getTime() - 7 * 24 * 3600_000);

    await this.prisma.mediaAsset.updateMany({
      where: {
        deletedAt: null,
        OR: [
          { status: { in: ['PENDING_UPLOAD', 'FAILED'] }, createdAt: { lt: day } },
          { status: 'READY', purpose: { in: ['POST', 'MESSAGE'] }, createdAt: { lt: week }, postMedia: null, attachment: null },
          { purpose: { in: ['AVATAR', 'COVER'] }, createdAt: { lt: week }, avatarOf: null, coverOf: null },
        ],
      },
      data: { deletedAt: now },
    });

    let deleted = 0;
    for (;;) {
      const batch = await this.prisma.mediaAsset.findMany({ where: { deletedAt: { not: null } }, take: BATCH, select: { id: true, objectKey: true, variants: true } });
      if (batch.length === 0) break;
      const keys = batch.flatMap((a) => [a.objectKey, ...Object.values((a.variants ?? {}) as MediaVariants).flatMap((v) => (v?.key ? [v.key] : []))]);
      await this.storage.deleteMany(keys);
      await this.prisma.mediaAsset.deleteMany({ where: { id: { in: batch.map((a) => a.id) } } });
      deleted += batch.length;
      if (batch.length < BATCH) break;
    }
    if (deleted) this.logger.log(`media cleanup removed ${deleted} assets`);
    return { deleted };
  }
}
