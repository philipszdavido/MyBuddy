import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { createHarness, Harness } from './harness';

/**
 * Cross-language contract test: compiles the iOS app's real API layer (ios/MyBuddy/Data/API + Domain)
 * for macOS with swiftc and runs it against this backend. Catches drift between the Swift models and
 * the JSON the server actually returns, and exercises the hand-written Socket.IO client end to end.
 * Skipped where swiftc is unavailable (e.g. Linux CI without a Swift toolchain).
 */
const ios = resolve(__dirname, '../../ios/MyBuddy');
const hasSwift = spawnSync('swiftc', ['--version']).status === 0 && existsSync(ios);
const maybe = hasSwift ? describe : describe.skip;

maybe('iOS API layer ↔ backend contract', () => {
  let h: Harness;
  let binary: string;

  beforeAll(async () => {
    h = await createHarness();
    const out = join(tmpdir(), 'mybuddy-ios-contract');
    mkdirSync(out, { recursive: true });
    binary = join(out, 'driver');
    const sources = [
      ...readdirSync(join(ios, 'Domain')).filter((f) => f.endsWith('.swift')).map((f) => join(ios, 'Domain', f)),
      join(ios, 'Core/AppError.swift'),
      join(ios, 'Core/Log.swift'),
      ...['APIClient', 'RealtimeClient', 'APIModels', 'APIRepositories', 'APIMessagingRepository'].map((f) => join(ios, `Data/API/${f}.swift`)),
      join(__dirname, 'ios-contract/main.swift'),
    ];
    execFileSync('swiftc', ['-O', '-o', binary, ...sources], { stdio: 'inherit' });
  }, 300_000);

  afterAll(() => h.close());

  it('the Swift client works against the real API (REST, realtime, uploads)', async () => {
    const a = await h.user('swift-a', { username: 'swifta', phone: '2349000000001' });
    const b = await h.user('swift-b', { username: 'swiftb', phone: '2349000000002' });
    // B has A in contacts so B can see A's CONTACTS posts; A syncs B from Swift.
    await h.http().post('/api/v1/contacts/sync').set(b.auth).send({ phoneNumbers: ['2349000000001'] }).expect(201);

    const env = {
      ...process.env,
      MB_URL: h.url,
      MB_TOKEN_A: a.auth.Authorization.replace('Bearer ', ''),
      MB_TOKEN_B: b.auth.Authorization.replace('Bearer ', ''),
      MB_UID_A: a.uid,
      MB_ID_B: b.id,
      MB_PHONE_A: '2349000000001',
      MB_PHONE_B: '2349000000002',
    };
    const result = await new Promise<{ code: number | null; out: string }>((resolveRun) => {
      const child = spawn(binary, [], { env });
      let out = '';
      child.stdout.on('data', (d: Buffer) => (out += d.toString()));
      child.stderr.on('data', (d: Buffer) => (out += d.toString()));
      child.on('close', (code) => resolveRun({ code, out }));
    });
    // Background jobs (fan-out, media processing) run in this process while the driver waits.
    if (result.code !== 0) console.log(result.out);
    expect(result.out).toContain('ALL PASSED');
    expect(result.code).toBe(0);
  }, 120_000);
});
