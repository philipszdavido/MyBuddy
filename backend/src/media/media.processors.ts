import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { MediaAsset, Prisma } from '@prisma/client';
import { Job, UnrecoverableError } from 'bullmq';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { ProcessMediaJob, Q } from '../queues/queues';
import { MediaVariants } from './media-presenter.service';
import { StorageService } from './storage.service';

const MAX_VIDEO_SECONDS = 180;
const MAX_PIXELS = 60_000_000;

type ImageSpec = { name: 'thumb' | 'medium' | 'large'; width: number; height?: number; square?: boolean };

const IMAGE_SPECS: Record<MediaAsset['purpose'], ImageSpec[]> = {
  AVATAR: [{ name: 'thumb', width: 160, square: true }, { name: 'medium', width: 512, square: true }],
  COVER: [{ name: 'thumb', width: 600, height: 200 }, { name: 'medium', width: 1500, height: 500 }],
  POST: [{ name: 'thumb', width: 320 }, { name: 'medium', width: 1080 }, { name: 'large', width: 2048 }],
  MESSAGE: [{ name: 'thumb', width: 320 }, { name: 'medium', width: 1600 }],
};

const variantKey = (asset: Pick<MediaAsset, 'ownerId' | 'id'>, file: string) => `u/${asset.ownerId}/${asset.id}/${file}`;

/** Marks the asset FAILED once BullMQ has given up (last attempt or unrecoverable error). */
async function markFailedIfFinal(prisma: PrismaService, realtime: RealtimePublisher, job: Job<ProcessMediaJob> | undefined, error: Error) {
  if (!job) return;
  const final = error instanceof UnrecoverableError || job.attemptsMade >= (job.opts.attempts ?? 1);
  if (!final) return;
  const asset = await prisma.mediaAsset.findUnique({ where: { id: job.data.mediaId }, select: { ownerId: true, status: true } });
  if (!asset || asset.status !== 'PROCESSING') return;
  await prisma.mediaAsset.update({ where: { id: job.data.mediaId }, data: { status: 'FAILED', error: error.message.slice(0, 500) } });
  await realtime.toUsers([asset.ownerId], 'media:updated', { mediaId: job.data.mediaId, status: 'FAILED' });
}

/**
 * Images are always re-encoded: EXIF orientation applied, all metadata (GPS!) stripped, never upscaled.
 * Serving only re-encoded variants also neutralises payloads hidden in the original file, which is deleted.
 */
@Processor(Q.media, { concurrency: Number(process.env.WORKER_CONCURRENCY ?? 5) })
export class ImageProcessor extends WorkerHost {
  private readonly logger = new Logger(ImageProcessor.name);

  constructor(private readonly prisma: PrismaService, private readonly storage: StorageService, private readonly realtime: RealtimePublisher) {
    super();
  }

  async process(job: Job<ProcessMediaJob>): Promise<{ variants: number }> {
    const asset = await this.prisma.mediaAsset.findUnique({ where: { id: job.data.mediaId } });
    if (!asset || asset.status !== 'PROCESSING' || asset.deletedAt) return { variants: 0 }; // already done or removed
    const original = await this.storage.download(asset.objectKey);

    let meta: sharp.Metadata;
    try {
      meta = await sharp(original, { limitInputPixels: MAX_PIXELS, failOn: 'error' }).metadata();
    } catch (error) {
      throw new UnrecoverableError(`not a decodable image: ${(error as Error).message}`);
    }
    const oriented = (meta.orientation ?? 1) >= 5; // 90° rotations swap width/height
    const width = oriented ? meta.height : meta.width;
    const height = oriented ? meta.width : meta.height;

    const variants: MediaVariants = {};
    for (const spec of IMAGE_SPECS[asset.purpose]) {
      const pipeline = sharp(original, { limitInputPixels: MAX_PIXELS, failOn: 'error' }).rotate();
      const resized = spec.square
        ? pipeline.resize(spec.width, spec.width, { fit: 'cover', position: 'attention', withoutEnlargement: true })
        : spec.height
          ? pipeline.resize(spec.width, spec.height, { fit: 'cover', withoutEnlargement: true })
          : pipeline.resize({ width: spec.width, withoutEnlargement: true });
      const { data, info } = await resized.jpeg({ quality: 82, mozjpeg: true, progressive: true }).toBuffer({ resolveWithObject: true });
      const key = variantKey(asset, `${spec.name}.jpg`);
      await this.storage.put(key, data, 'image/jpeg');
      variants[spec.name] = { key, width: info.width, height: info.height, mimeType: 'image/jpeg' };
      await job.updateProgress(Math.round((Object.keys(variants).length / IMAGE_SPECS[asset.purpose].length) * 100));
    }

    await this.prisma.mediaAsset.update({
      where: { id: asset.id },
      data: { status: 'READY', variants: variants as Prisma.InputJsonValue, width, height, processedAt: new Date(), error: null },
    });
    await this.storage.delete(asset.objectKey).catch((e: unknown) => this.logger.warn(`original not deleted: ${String(e)}`));
    await this.realtime.toUsers([asset.ownerId], 'media:updated', { mediaId: asset.id, status: 'READY' });
    return { variants: Object.keys(variants).length };
  }

  @OnWorkerEvent('failed')
  async onFailed(job: Job<ProcessMediaJob> | undefined, error: Error) {
    await markFailedIfFinal(this.prisma, this.realtime, job, error);
  }
}

interface Probe {
  durationSeconds: number;
  width: number;
  height: number;
  hasAudio: boolean;
}

/** Asynchronous video pipeline: validate (ffprobe), poster frame, H.264/AAC MP4 renditions with faststart. */
@Processor(Q.video, { concurrency: 1, lockDuration: 10 * 60_000 })
export class VideoProcessor extends WorkerHost {
  private readonly logger = new Logger(VideoProcessor.name);

  constructor(private readonly prisma: PrismaService, private readonly storage: StorageService, private readonly realtime: RealtimePublisher) {
    super();
  }

  async process(job: Job<ProcessMediaJob>): Promise<{ renditions: number }> {
    const asset = await this.prisma.mediaAsset.findUnique({ where: { id: job.data.mediaId } });
    if (!asset || asset.status !== 'PROCESSING' || asset.deletedAt) return { renditions: 0 };
    const dir = await mkdtemp(join(tmpdir(), 'mb-video-'));
    try {
      const input = join(dir, 'input');
      await writeFile(input, await this.storage.download(asset.objectKey));
      const probe = await this.probe(input);
      if (probe.durationSeconds > MAX_VIDEO_SECONDS + 1) {
        throw new UnrecoverableError(`video is longer than ${MAX_VIDEO_SECONDS} seconds`);
      }
      await job.updateProgress(10);

      const variants: MediaVariants = {};
      const poster = join(dir, 'poster.jpg');
      const at = Math.min(1, probe.durationSeconds / 2).toFixed(2);
      await run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-ss', at, '-i', input, '-frames:v', '1', '-vf', "scale='min(1080,iw)':-2", '-q:v', '3', '-y', poster]);
      const posterBuf = await readFile(poster);
      const posterMeta = await sharp(posterBuf).metadata();
      variants.poster = { key: variantKey(asset, 'poster.jpg'), width: posterMeta.width, height: posterMeta.height, mimeType: 'image/jpeg' };
      await this.storage.put(variants.poster.key, posterBuf, 'image/jpeg');
      await job.updateProgress(25);

      const shortSide = Math.min(probe.width, probe.height);
      const targets = ([['mp4_720', 720], ['mp4_480', 480]] as const).filter(([, h], i) => i === 0 || shortSide > h);
      for (const [name, size] of targets) {
        const out = join(dir, `${name}.mp4`);
        const scale = `scale='if(gt(iw,ih),-2,min(${size},iw))':'if(gt(iw,ih),min(${size},ih),-2)'`;
        await run('ffmpeg', [
          '-hide_banner', '-loglevel', 'error', '-i', input, '-map', '0:v:0', '-map', '0:a:0?',
          '-vf', scale, '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-b:a', '128k', '-ac', '2', '-movflags', '+faststart', '-map_metadata', '-1', '-y', out,
        ]);
        const p = await this.probe(out);
        variants[name] = { key: variantKey(asset, `${name}.mp4`), width: p.width, height: p.height, mimeType: 'video/mp4' };
        await this.storage.put(variants[name].key, await readFile(out), 'video/mp4');
        await job.updateProgress(25 + Math.round((65 * Object.keys(variants).filter((k) => k.startsWith('mp4')).length) / targets.length));
      }

      await this.prisma.mediaAsset.update({
        where: { id: asset.id },
        data: {
          status: 'READY',
          variants: variants as Prisma.InputJsonValue,
          width: probe.width,
          height: probe.height,
          durationMs: Math.round(probe.durationSeconds * 1000),
          processedAt: new Date(),
          error: null,
        },
      });
      await this.storage.delete(asset.objectKey).catch((e: unknown) => this.logger.warn(`original not deleted: ${String(e)}`));
      await job.updateProgress(100);
      await this.realtime.toUsers([asset.ownerId], 'media:updated', { mediaId: asset.id, status: 'READY' });
      return { renditions: targets.length };
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }

  private async probe(file: string): Promise<Probe> {
    let raw: string;
    try {
      raw = await run('ffprobe', ['-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', file]);
    } catch (error) {
      throw new UnrecoverableError(`not a decodable video: ${(error as Error).message}`);
    }
    const data = JSON.parse(raw) as { streams?: Array<{ codec_type?: string; width?: number; height?: number; side_data_list?: Array<{ rotation?: number }> }>; format?: { duration?: string } };
    const video = data.streams?.find((s) => s.codec_type === 'video');
    if (!video?.width || !video.height) throw new UnrecoverableError('file has no video stream');
    const rotated = Math.abs(video.side_data_list?.find((s) => s.rotation !== undefined)?.rotation ?? 0) % 180 === 90;
    return {
      durationSeconds: Number(data.format?.duration ?? 0),
      width: rotated ? video.height : video.width,
      height: rotated ? video.width : video.height,
      hasAudio: !!data.streams?.some((s) => s.codec_type === 'audio'),
    };
  }

  @OnWorkerEvent('failed')
  async onFailed(job: Job<ProcessMediaJob> | undefined, error: Error) {
    await markFailedIfFinal(this.prisma, this.realtime, job, error);
  }
}

/** Runs a binary with arguments (no shell, so no injection), resolving with stdout. */
function run(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    child.stdout.on('data', (d: Buffer) => (out += d.toString()));
    child.stderr.on('data', (d: Buffer) => (err += d.toString()));
    child.on('error', reject);
    child.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} exited ${code}: ${err.slice(-500)}`))));
  });
}
