import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { Q } from '../src/queues/queues';
import { createHarness, Harness, TestUser } from './harness';

const api = '/api/v1';

describe('media uploads via presigned R2 URLs (integration)', () => {
  let h: Harness;
  let ada: TestUser;
  let bola: TestUser;

  beforeAll(async () => {
    h = await createHarness();
    ada = await h.user('m-ada', { username: 'mada' });
    bola = await h.user('m-bola', { username: 'mbola' });
  });
  afterAll(() => h.close());

  async function upload(u: TestUser, purpose: string, mimeType: string, body: Buffer, declared = body.length) {
    const ticket = await h.http().post(`${api}/media/upload-url`).set(u.auth).send({ purpose, mimeType, sizeBytes: declared }).expect(201);
    const put = await fetch(ticket.body.uploadUrl, { method: 'PUT', headers: { 'Content-Type': mimeType }, body });
    expect(put.ok).toBe(true);
    return ticket.body.mediaId as string;
  }

  it('uploads, verifies and processes an image into stripped, resized variants', async () => {
    const jpeg = await sharp({ create: { width: 3000, height: 2000, channels: 3, background: '#3366cc' } })
      .jpeg().withMetadata({ exif: { IFD0: { Make: 'SecretCam' } } }).toBuffer();
    const mediaId = await upload(ada, 'POST', 'image/jpeg', jpeg);
    const done = await h.http().post(`${api}/media/complete`).send({ mediaId }).set(ada.auth).expect(201);
    expect(done.body.status).toBe('PROCESSING');
    await h.drain(Q.media);

    const media = await h.http().get(`${api}/media/${mediaId}`).set(ada.auth).expect(200);
    expect(media.body).toMatchObject({ status: 'READY', kind: 'IMAGE', width: 3000, height: 2000 });
    expect(Object.keys(media.body.urls).sort()).toEqual(['large', 'medium', 'thumb']);
    await h.http().get(`${api}/media/${mediaId}`).set(bola.auth).expect(404); // owner only

    const large = Buffer.from(await (await fetch(media.body.urls.large)).arrayBuffer());
    const meta = await sharp(large).metadata();
    expect(meta.width).toBe(2048);
    expect(meta.exif).toBeUndefined(); // metadata stripped
    const original = await h.prisma.mediaAsset.findUniqueOrThrow({ where: { id: mediaId } });
    expect((await fetch(`${process.env.R2_PUBLIC_URL}/${original.objectKey}`)).status).toBe(404); // original removed

    const post = await h.http().post(`${api}/posts`).set(ada.auth).send({ text: 'photo', mediaIds: [mediaId], audience: 'PUBLIC' }).expect(201);
    expect(post.body).toMatchObject({ kind: 'image', media: [{ id: mediaId, status: 'READY' }] });
    // media can't be attached twice, or by someone else
    await h.http().post(`${api}/posts`).set(ada.auth).send({ mediaIds: [mediaId] }).expect(400);
    await h.http().delete(`${api}/media/${mediaId}`).set(ada.auth).expect(409);
  });

  it('rejects files whose real content is not an allowed type, whatever they declare', async () => {
    const fake = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
    const mediaId = await upload(ada, 'POST', 'image/png', fake);
    const res = await h.http().post(`${api}/media/complete`).send({ mediaId }).set(ada.auth).expect(415);
    expect(res.body.error.code).toBe('UNSUPPORTED_MEDIA');
    expect((await h.prisma.mediaAsset.findUniqueOrThrow({ where: { id: mediaId } })).status).toBe('FAILED');
  });

  it('enforces declared size and per-purpose limits and types', async () => {
    const jpeg = await sharp({ create: { width: 10, height: 10, channels: 3, background: '#000' } }).jpeg().toBuffer();
    const mediaId = await upload(ada, 'POST', 'image/jpeg', Buffer.concat([jpeg, Buffer.alloc(100)]), jpeg.length + 100);
    // Simulate a store that did not enforce the signed length: declared size is re-checked server-side.
    await h.prisma.mediaAsset.update({ where: { id: mediaId }, data: { declaredBytes: BigInt(jpeg.length) } });
    await h.http().post(`${api}/media/complete`).send({ mediaId }).set(ada.auth).expect(413);

    await h.http().post(`${api}/media/upload-url`).set(ada.auth).send({ purpose: 'AVATAR', mimeType: 'image/jpeg', sizeBytes: 50 * 1024 * 1024 }).expect(413);
    await h.http().post(`${api}/media/upload-url`).set(ada.auth).send({ purpose: 'AVATAR', mimeType: 'video/mp4', sizeBytes: 1000 }).expect(415);
    const heic = await h.http().post(`${api}/media/upload-url`).set(ada.auth).send({ purpose: 'POST', mimeType: 'image/heic', sizeBytes: 1000 }).expect(415);
    expect(heic.body.error.message).toMatch(/JPEG/);
  });

  it('sets a processed avatar on the profile', async () => {
    const png = await sharp({ create: { width: 800, height: 600, channels: 4, background: '#ff0000' } }).png().toBuffer();
    const mediaId = await upload(ada, 'AVATAR', 'image/png', png);
    await h.http().patch(`${api}/users/me`).set(ada.auth).send({ avatarMediaId: mediaId }).expect(409); // not processed yet
    await h.http().post(`${api}/media/complete`).send({ mediaId }).set(ada.auth).expect(201);
    await h.drain(Q.media);
    const me = await h.http().patch(`${api}/users/me`).set(ada.auth).send({ avatarMediaId: mediaId }).expect(200);
    expect(me.body.avatarUrl).toMatch(/medium\.jpg$/);
    const avatar = await sharp(Buffer.from(await (await fetch(me.body.avatarUrl)).arrayBuffer())).metadata();
    expect([avatar.width, avatar.height]).toEqual([512, 512]);
    await h.http().patch(`${api}/users/me`).set(bola.auth).send({ avatarMediaId: mediaId }).expect(404); // not bola's
  });

  it('transcodes video into a poster and H.264 renditions', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'mbt-'));
    const file = join(dir, 'in.mov');
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=24', '-f', 'lavfi', '-i', 'sine=frequency=440',
      '-t', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-f', 'mov', file]);
    const mediaId = await upload(ada, 'POST', 'video/quicktime', readFileSync(file));
    await h.http().post(`${api}/media/complete`).send({ mediaId }).set(ada.auth).expect(201);
    await h.drain(Q.video);
    const media = await h.http().get(`${api}/media/${mediaId}`).set(ada.auth).expect(200);
    expect(media.body).toMatchObject({ status: 'READY', kind: 'VIDEO', width: 1280, height: 720 });
    expect(media.body.durationMs).toBeGreaterThan(1500);
    expect(Object.keys(media.body.urls).sort()).toEqual(['mp4_480', 'mp4_720', 'poster']);
    const mp4 = Buffer.from(await (await fetch(media.body.urls.mp4_720)).arrayBuffer());
    expect(mp4.subarray(4, 8).toString('latin1')).toBe('ftyp');
  }, 60_000);
});
