import { io, Socket } from 'socket.io-client';
import { Q } from '../src/queues/queues';
import { createHarness, Harness, TestUser } from './harness';

const api = '/api/v1';

type Ack<T = unknown> = { ok: true; data: T } | { ok: false; error: { code: string } };

describe('messaging, realtime and notifications (integration)', () => {
  let h: Harness;
  let ada: TestUser;
  let bola: TestUser;
  let chi: TestUser; // outsider
  const sockets: Socket[] = [];

  const connect = (token: string) =>
    new Promise<Socket>((resolve, reject) => {
      const s = io(`${h.url}/realtime`, { auth: { token }, transports: ['websocket'], forceNew: true, reconnection: false });
      sockets.push(s);
      s.once('ready', () => resolve(s));
      s.once('error', (e: unknown) => reject(new Error(JSON.stringify(e))));
      s.once('connect_error', reject);
    });
  const tokenOf = (u: TestUser) => u.auth.Authorization.replace('Bearer ', '');
  const emit = <T>(s: Socket, event: string, body?: unknown) => new Promise<Ack<T>>((resolve) => s.emit(event, body, resolve));
  const next = <T>(s: Socket, event: string, ms = 3000) =>
    new Promise<T>((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`no ${event} within ${ms}ms`)), ms);
      s.once(event, (payload: T) => {
        clearTimeout(t);
        resolve(payload);
      });
    });

  beforeAll(async () => {
    h = await createHarness();
    ada = await h.user('w-ada', { username: 'wada', phone: '2347000000001' });
    bola = await h.user('w-bola', { username: 'wbola', phone: '2347000000002' });
    chi = await h.user('w-chi', { username: 'wchi' });
    // ada and bola are contacts of each other (as in the pre-rebuild app)
    await h.http().post(`${api}/contacts/sync`).set(ada.auth).send({ phoneNumbers: ['2347000000002'] }).expect(201);
    await h.http().post(`${api}/contacts/sync`).set(bola.auth).send({ phoneNumbers: ['2347000000001'] }).expect(201);
  });
  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    await h.close();
  });

  let conversationId: string;

  it('creates one direct conversation per pair and sends idempotently with gap-free seq', async () => {
    const c1 = await h.http().post(`${api}/conversations`).set(ada.auth).send({ participantIds: [bola.id] }).expect(201);
    const c2 = await h.http().post(`${api}/conversations`).set(bola.auth).send({ participantIds: [ada.id] }).expect(201);
    expect(c2.body.id).toBe(c1.body.id);
    expect(c1.body).toMatchObject({ kind: 'DIRECT', isRequest: false });
    conversationId = c1.body.id;

    const m1 = await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-1', text: 'hi bola' }).expect(201);
    const again = await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-1', text: 'hi bola' }).expect(201);
    expect(again.body.id).toBe(m1.body.id);
    const m2 = await h.http().post(`${api}/conversations/${conversationId}/messages`).set(bola.auth).send({ clientId: 'b-1', text: 'hey', replyToId: m1.body.id }).expect(201);
    expect([m1.body.seq, m2.body.seq]).toEqual([1, 2]);
    expect(m2.body.replyTo).toMatchObject({ id: m1.body.id, text: 'hi bola' });

    // Replying counts as reading: bola has nothing unread, ada has bola's reply.
    expect((await h.http().get(`${api}/conversations`).set(bola.auth).expect(200)).body.items[0]).toMatchObject({ id: conversationId, unreadCount: 0 });
    const list = await h.http().get(`${api}/conversations`).set(ada.auth).expect(200);
    expect(list.body.items[0]).toMatchObject({ id: conversationId, unreadCount: 1, lastMessage: { text: 'hey' } });
    await h.http().post(`${api}/conversations/${conversationId}/read`).set(ada.auth).send({ seq: 999 }).expect(201, { lastReadSeq: 2 });
    expect((await h.http().get(`${api}/conversations/unread-count`).set(ada.auth).expect(200)).body).toEqual({ unread: 0 });
  });

  it('outsiders cannot read or write a conversation, over REST or sockets', async () => {
    await h.http().get(`${api}/conversations/${conversationId}/messages`).set(chi.auth).expect(404);
    await h.http().post(`${api}/conversations/${conversationId}/messages`).set(chi.auth).send({ clientId: 'x', text: 'intrude' }).expect(404);
    const s = await connect(tokenOf(chi));
    const ack = await emit(s, 'message:send', { conversationId, clientId: 'c-x', text: 'intrude' });
    expect(ack).toEqual({ ok: false, error: { code: 'NOT_FOUND', message: expect.any(String) } });
    const typing = await emit(s, 'typing', { conversationId, isTyping: true });
    expect(typing.ok).toBe(false);
  });

  it('rejects sockets with invalid tokens', async () => {
    await expect(connect('garbage')).rejects.toThrow(/UNAUTHENTICATED/);
  });

  it('delivers messages, typing and read receipts in real time', async () => {
    const a = await connect(tokenOf(ada));
    const b = await connect(tokenOf(bola));
    const incoming = next<{ text: string; seq: number; senderId: string }>(b, 'message:new');
    const ack = await emit<{ id: string; seq: number }>(a, 'message:send', { conversationId, clientId: 'a-2', text: 'live!' });
    expect(ack.ok).toBe(true);
    const msg = await incoming;
    expect(msg).toMatchObject({ text: 'live!', seq: 3, senderId: ada.id });

    const typing = next<{ userId: string; isTyping: boolean }>(b, 'typing');
    await emit(a, 'typing', { conversationId, isTyping: true });
    expect(await typing).toEqual({ conversationId, userId: ada.id, isTyping: true });

    const receipt = next<{ userId: string; seq: number }>(a, 'conversation:read');
    await emit(b, 'conversation:read', { conversationId, seq: 3 });
    expect(await receipt).toEqual({ conversationId, userId: bola.id, seq: 3 });

    const bad = await emit(a, 'message:send', { conversationId, clientId: 'a-3', text: 'x', role: 'ADMIN' });
    expect(bad).toMatchObject({ ok: false, error: { code: 'VALIDATION_FAILED' } });
  });

  it('a reconnecting client catches up from PostgreSQL with afterSeq (no lost messages)', async () => {
    // bola is offline while ada sends two messages
    await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-4', text: 'while you were away 1' }).expect(201);
    await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-5', text: 'while you were away 2' }).expect(201);
    const missed = await h.http().get(`${api}/conversations/${conversationId}/messages?afterSeq=3`).set(bola.auth).expect(200);
    expect(missed.body.items.map((m: { seq: number }) => m.seq)).toEqual([4, 5]);
    const history = await h.http().get(`${api}/conversations/${conversationId}/messages?beforeSeq=3&limit=1`).set(bola.auth).expect(200);
    expect(history.body).toMatchObject({ items: [{ seq: 2 }], hasMore: true });
  });

  it('edits within the window, deletes for everyone, reacts', async () => {
    const m = (await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-6', text: 'typo' }).expect(201)).body;
    await h.http().patch(`${api}/messages/${m.id}`).set(bola.auth).send({ text: 'not yours' }).expect(404);
    expect((await h.http().patch(`${api}/messages/${m.id}`).set(ada.auth).send({ text: 'fixed' }).expect(200)).body).toMatchObject({ text: 'fixed', editedAt: expect.any(String) });
    const reacted = await h.http().post(`${api}/messages/${m.id}/reactions`).set(bola.auth).send({ emoji: '❤️' }).expect(201);
    expect(reacted.body.reactions).toEqual([{ emoji: '❤️', count: 1, mine: true }]);
    await h.http().delete(`${api}/messages/${m.id}`).set(ada.auth).expect(204);
    const after = await h.http().get(`${api}/conversations/${conversationId}/messages?afterSeq=${m.seq - 1}`).set(bola.auth).expect(200);
    expect(after.body.items[0]).toMatchObject({ id: m.id, deleted: true, text: null, reactions: [] });
  });

  it('routes strangers into message requests and honours the recipient’s messaging setting', async () => {
    const c = await h.http().post(`${api}/conversations`).set(chi.auth).send({ participantIds: [ada.id] }).expect(201);
    await h.http().post(`${api}/conversations/${c.body.id}/messages`).set(chi.auth).send({ clientId: 'c-1', text: 'hello stranger' }).expect(201);
    await h.http().post(`${api}/conversations/${c.body.id}/messages`).set(chi.auth).send({ clientId: 'c-2', text: 'hello again' }).expect(201);
    const inbox = await h.http().get(`${api}/conversations`).set(ada.auth).expect(200);
    expect(inbox.body.items.map((x: { id: string }) => x.id)).not.toContain(c.body.id);
    const requests = await h.http().get(`${api}/conversations?requests=true`).set(ada.auth).expect(200);
    expect(requests.body.items.map((x: { id: string }) => x.id)).toEqual([c.body.id]);
    expect(await h.prisma.notification.count({ where: { recipientId: ada.id, type: 'MESSAGE_REQUEST' } })).toBe(1);
    await h.http().post(`${api}/conversations/${c.body.id}/accept`).set(ada.auth).expect(201);

    await h.http().patch(`${api}/users/me/settings`).set(bola.auth).send({ allowMessagesFrom: 'CONNECTIONS' }).expect(200);
    await h.http().post(`${api}/conversations`).set(chi.auth).send({ participantIds: [bola.id] }).expect(403);
  });

  it('blocking stops messages in an existing conversation', async () => {
    await h.http().post(`${api}/users/${chi.id}/block`).set(ada.auth).expect(204);
    const c = await h.http().get(`${api}/conversations?requests=false`).set(chi.auth).expect(200);
    const id = c.body.items.find((x: { participants: Array<{ id: string }> }) => x.participants.some((p) => p.id === ada.id))?.id as string;
    const res = await h.http().post(`${api}/conversations/${id}/messages`).set(chi.auth).send({ clientId: 'c-3', text: 'still there?' }).expect(403);
    expect(res.body.error.code).toBe('BLOCKED');
  });

  it('sends FCM pushes without message content, to every device, pruning dead tokens', async () => {
    await h.http().put(`${api}/devices/inst-1`).set(bola.auth).send({ fcmToken: 'tok-bola-phone', platform: 'ios' }).expect(204);
    await h.http().put(`${api}/devices/inst-2`).set(bola.auth).send({ fcmToken: 'dead-token', platform: 'ios' }).expect(204);
    await h.drain(Q.notifications);
    h.fcm.sent = [];
    const m = await h.http().post(`${api}/conversations/${conversationId}/messages`).set(ada.auth).send({ clientId: 'a-7', text: 'secret plans' }).expect(201);
    await h.drain(Q.notifications);
    expect(h.fcm.sent).toHaveLength(1);
    const push = h.fcm.sent[0];
    expect(push.token).toBe('tok-bola-phone');
    expect(push.message.data).toMatchObject({ deepLink: `mybuddy://chat/${conversationId}`, chatId: conversationId, type: 'MESSAGE' });
    expect(JSON.stringify(push.message)).not.toContain('secret plans');
    expect(push.message.badge).toBeGreaterThanOrEqual(1);
    expect(await h.prisma.userDevice.count({ where: { userId: bola.id } })).toBe(1); // dead token removed
    expect(await h.prisma.notification.count({ where: { pushProcessedAt: null, dedupeKey: `MESSAGE:${m.body.id}` } })).toBe(0);

    // the same physical device signing in as another account takes the token over
    await h.http().put(`${api}/devices/inst-9`).set(chi.auth).send({ fcmToken: 'tok-bola-phone', platform: 'ios' }).expect(204);
    expect(await h.prisma.userDevice.count({ where: { userId: bola.id } })).toBe(0);
  });

  it('activity inbox: deep links, read state and push preferences', async () => {
    await h.http().put(`${api}/devices/inst-3`).set(ada.auth).send({ fcmToken: 'tok-ada', platform: 'ios' }).expect(204);
    await h.http().patch(`${api}/notifications/preferences`).set(ada.auth).send({ preferences: [{ type: 'FOLLOW', push: false }] }).expect(200);
    h.fcm.sent = [];
    await h.http().post(`${api}/users/${ada.id}/follow`).set(bola.auth).expect(201);
    await h.drain(Q.notifications);
    expect(h.fcm.sent.filter((p) => p.message.data.type === 'FOLLOW')).toHaveLength(0);

    const inbox = await h.http().get(`${api}/notifications`).set(ada.auth).expect(200);
    const follow = inbox.body.items.find((n: { type: string }) => n.type === 'FOLLOW');
    expect(follow).toMatchObject({ actor: { id: bola.id }, deepLink: `mybuddy://profile/${bola.id}`, read: false });
    expect(inbox.body.items.some((n: { type: string }) => n.type === 'MESSAGE')).toBe(false);
    await h.http().patch(`${api}/notifications/${follow.id}/read`).set(ada.auth).expect(204);
    await h.http().patch(`${api}/notifications/${follow.id}/read`).set(bola.auth).expect(404);
    await h.http().patch(`${api}/notifications/read-all`).set(ada.auth).expect(200);

    // Hiding a type from Activity removes it from the inbox (push follows its own switch).
    await h.http().patch(`${api}/notifications/preferences`).set(ada.auth).send({ preferences: [{ type: 'FOLLOW', inApp: false }] }).expect(200);
    const hidden = await h.http().get(`${api}/notifications`).set(ada.auth).expect(200);
    expect(hidden.body.items.some((n: { type: string }) => n.type === 'FOLLOW')).toBe(false);
    expect((await h.http().get(`${api}/notifications/unread-count`).set(ada.auth).expect(200)).body).toEqual({ unread: 0 });
  });

  it('reports presence to allowed watchers only', async () => {
    const a = await connect(tokenOf(ada));
    const b = await connect(tokenOf(bola));
    const ack = await emit<Array<{ userId: string; online: boolean }>>(b, 'presence:subscribe', { userIds: [ada.id, chi.id] });
    expect(ack.ok && ack.data.find((p) => p.userId === ada.id)?.online).toBe(true);
    const changed = next<{ userId: string; online: boolean }>(b, 'presence', 5000);
    // close every ada socket, then she goes offline
    sockets.filter((s) => s !== b && s.connected && (s as unknown as { auth: { token: string } }).auth.token === tokenOf(ada)).forEach((s) => s.disconnect());
    a.disconnect();
    expect(await changed).toMatchObject({ userId: ada.id, online: false });
    // ada blocked chi earlier, so chi gets no presence for ada
    const presence = await h.http().get(`${api}/presence?ids=${ada.id}`).set(chi.auth).expect(200);
    expect(presence.body).toEqual([]);
  });
});
