import { createHarness, Harness } from './harness';

describe('auth + users (integration)', () => {
  let h: Harness;

  beforeAll(async () => {
    h = await createHarness();
  });
  afterAll(() => h.close());

  it('serves liveness and readiness without auth', async () => {
    await h.http().get('/health/live').expect(200, { status: 'ok' });
    const ready = await h.http().get('/health/ready').expect(200);
    expect(ready.body.info).toMatchObject({ postgres: { status: 'up' }, redis: { status: 'up' } });
  });

  it('rejects requests without a valid token in the standard error envelope', async () => {
    const res = await h.http().get('/api/v1/users/me').expect(401);
    expect(res.body).toEqual({ error: expect.objectContaining({ code: 'UNAUTHENTICATED' }) });
    await h.http().get('/api/v1/users/me').set('Authorization', 'Bearer garbage').expect(401);
  });

  it('provisions a PostgreSQL user on the first request, once, even under concurrency', async () => {
    const auth = { Authorization: 'Bearer test:race-uid:race@example.com:v' };
    const results = await Promise.all(Array.from({ length: 5 }, () => h.http().get('/api/v1/users/me').set(auth)));
    expect(results.map((r) => r.status)).toEqual([200, 200, 200, 200, 200]);
    expect(new Set(results.map((r) => (r.body as { id: string }).id)).size).toBe(1);
    expect(await h.prisma.user.count({ where: { firebaseUid: 'race-uid' } })).toBe(1);
    expect(results[0].body).toMatchObject({ email: 'race@example.com', emailVerified: true, displayName: 'race', role: 'USER' });
  });

  it('takes the verified phone number from the token, not from the client', async () => {
    const auth = { Authorization: 'Bearer test:phone-uid:p@example.com:v:+2348012345678' };
    await h.http().get('/api/v1/users/me').set(auth).expect(200);
    const res = await h.http().patch('/api/v1/users/me').set(auth).send({ phoneNumber: '15550001111' }).expect(200);
    expect(res.body).toMatchObject({ phoneNumber: '2348012345678', phoneVerified: true });
  });

  it('rejects protected fields instead of silently accepting them', async () => {
    const a = await h.user('mass-assign');
    const res = await h.http().patch('/api/v1/users/me').set(a.auth).send({ role: 'ADMIN', isVerified: true }).expect(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
    expect((await h.prisma.user.findUniqueOrThrow({ where: { id: a.id } })).role).toBe('USER');
  });

  it('enforces unique, well-formed usernames', async () => {
    const a = await h.user('uname-a', { username: 'ada' });
    const b = await h.user('uname-b');
    const taken = await h.http().patch('/api/v1/users/me').set(b.auth).send({ username: 'ADA' }).expect(409);
    expect(taken.body.error.code).toBe('USERNAME_TAKEN');
    await h.http().patch('/api/v1/users/me').set(b.auth).send({ username: 'no spaces' }).expect(400);
    await h.http().get('/api/v1/users/username-available?username=ada').set(b.auth).expect(200, { username: 'ada', available: false });
    const view = await h.http().get('/api/v1/users/ada').set(b.auth).expect(200);
    expect(view.body).toMatchObject({ id: a.id, username: 'ada', relationship: expect.objectContaining({ following: false }) });
    expect(view.body).not.toHaveProperty('email');
    expect(view.body.relationship).not.toHaveProperty('blockedBy');
  });

  it('hides a profile from users the owner has blocked', async () => {
    const owner = await h.user('blocker', { username: 'blocker' });
    const other = await h.user('blocked-one');
    await h.prisma.userBlock.create({ data: { blockerId: owner.id, blockedId: other.id } });
    await h.http().get('/api/v1/users/blocker').set(other.auth).expect(404);
  });

  it('locks the account and schedules deletion', async () => {
    const a = await h.user('deleter');
    await h.http().delete('/api/v1/users/me').set(a.auth).expect(202, { status: 'scheduled' });
    expect(h.verifier.revoked.has('deleter')).toBe(true);
    expect((await h.prisma.user.findUniqueOrThrow({ where: { id: a.id } })).status).toBe('DELETING');
    await h.http().get('/api/v1/users/me').set(a.auth).expect(401);
    expect(await h.prisma.auditLog.count({ where: { action: 'account.delete_requested', actorId: a.id } })).toBe(1);
  });
});
