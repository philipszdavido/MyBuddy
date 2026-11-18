import { createHarness, Harness, TestUser } from './harness';

const api = '/api/v1';

describe('social graph, posts, engagement and feed (integration)', () => {
  let h: Harness;
  let ada: TestUser; // public, has bola in contacts
  let bola: TestUser; // contact of ada
  let chi: TestUser; // follows ada
  let dami: TestUser; // private account
  let eze: TestUser; // stranger with public posts

  const post = async (u: TestUser, body: Record<string, unknown>) =>
    (await h.http().post(`${api}/posts`).set(u.auth).send(body).expect(201)).body as { id: string; counts: Record<string, number> };
  const feedIds = async (u: TestUser) =>
    ((await h.http().get(`${api}/feed/following`).set(u.auth).expect(200)).body as { items: Array<{ id: string }> }).items.map((p) => p.id);

  beforeAll(async () => {
    h = await createHarness();
    ada = await h.user('ada', { username: 'ada', phone: '2348000000001' });
    bola = await h.user('bola', { username: 'bola', phone: '2348000000002' });
    chi = await h.user('chi', { username: 'chi' });
    dami = await h.user('dami', { username: 'dami', visibility: 'PRIVATE' });
    eze = await h.user('eze', { username: 'eze' });
  });
  afterAll(() => h.close());

  it('contact sync matches by phone number and contacts see CONTACTS posts (legacy behaviour)', async () => {
    const sync = await h.http().post(`${api}/contacts/sync`).set(ada.auth).send({ phoneNumbers: ['+234 800 000 0002', '999'] }).expect(201);
    expect(sync.body.matched.map((m: { id: string }) => m.id)).toEqual([bola.id]);

    const p = await post(ada, { text: 'hello contacts #MyBuddy', clientId: 'c-1' });
    // retry with the same clientId is idempotent
    expect((await post(ada, { text: 'hello contacts #MyBuddy', clientId: 'c-1' })).id).toBe(p.id);
    await h.drain();

    expect(await feedIds(bola)).toContain(p.id);
    expect(await feedIds(ada)).toContain(p.id);
    await h.http().get(`${api}/posts/${p.id}`).set(chi.auth).expect(404);
    expect((await h.prisma.userProfile.findUniqueOrThrow({ where: { userId: ada.id } })).postsCount).toBe(1);
    expect((await h.prisma.hashtag.findUniqueOrThrow({ where: { tag: 'mybuddy' } })).postCount).toBe(1);
  });

  it('follow: public accounts are followed immediately and followers receive FOLLOWERS posts', async () => {
    await h.http().post(`${api}/users/${chi.id}/follow`).set(chi.auth).expect(400); // not yourself
    expect((await h.http().post(`${api}/users/${ada.id}/follow`).set(chi.auth).expect(201)).body).toEqual({ state: 'following' });
    expect((await h.http().post(`${api}/users/${ada.id}/follow`).set(chi.auth).expect(201)).body).toEqual({ state: 'following' }); // idempotent
    const p = await post(ada, { text: 'for followers', audience: 'FOLLOWERS' });
    await h.drain();
    expect(await feedIds(chi)).toContain(p.id);
    expect(await feedIds(bola)).not.toContain(p.id); // contact, but not a follower
    const profile = await h.http().get(`${api}/users/ada`).set(chi.auth).expect(200);
    expect(profile.body).toMatchObject({ followersCount: 1, relationship: { following: true } });
    const followers = await h.http().get(`${api}/users/${ada.id}/followers`).set(bola.auth).expect(200);
    expect(followers.body.items.map((u: { id: string }) => u.id)).toEqual([chi.id]);
    expect(await h.prisma.notification.count({ where: { recipientId: ada.id, type: 'FOLLOW' } })).toBe(1);
  });

  it('private accounts require an accepted request before their posts become visible', async () => {
    const p = await post(dami, { text: 'private but public audience', audience: 'PUBLIC' });
    expect((await h.http().post(`${api}/users/${dami.id}/follow`).set(chi.auth).expect(201)).body).toEqual({ state: 'requested' });
    await h.http().get(`${api}/posts/${p.id}`).set(chi.auth).expect(404);
    await h.http().get(`${api}/users/${dami.id}/followers`).set(chi.auth).expect(403);

    const requests = await h.http().get(`${api}/follow-requests`).set(dami.auth).expect(200);
    expect(requests.body.items).toHaveLength(1);
    await h.http().post(`${api}/follow-requests/${requests.body.items[0].requestId}/respond`).set(dami.auth).send({ accept: true }).expect(204);
    await h.drain();
    await h.http().get(`${api}/posts/${p.id}`).set(chi.auth).expect(200);
    expect(await feedIds(chi)).toContain(p.id); // backfilled
    expect(await h.prisma.notification.count({ where: { recipientId: chi.id, type: 'FOLLOW_ACCEPTED' } })).toBe(1);
  });

  it('reactions are unique per user and counters survive concurrent taps', async () => {
    const p = await post(ada, { text: 'like me', audience: 'PUBLIC' });
    const taps = await Promise.all(Array.from({ length: 10 }, () => h.http().post(`${api}/posts/${p.id}/like`).set(chi.auth)));
    expect(taps.every((t) => t.status === 201)).toBe(true);
    let row = await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } });
    expect(row.likeCount).toBe(1);
    expect(await h.prisma.notification.count({ where: { recipientId: ada.id, type: 'POST_REACTION', postId: p.id } })).toBe(1);

    const switched = await h.http().post(`${api}/posts/${p.id}/reactions`).set(chi.auth).send({ type: 'DISLIKE' }).expect(201);
    expect(switched.body).toEqual({ likes: 0, dislikes: 1, mine: 'DISLIKE' });
    expect(await h.prisma.notification.count({ where: { recipientId: ada.id, type: 'POST_REACTION', postId: p.id } })).toBe(0);
    await h.http().delete(`${api}/posts/${p.id}/reactions`).set(chi.auth).expect(200, { likes: 0, dislikes: 0, mine: null });
    row = await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } });
    expect([row.likeCount, row.dislikeCount]).toEqual([0, 0]);
  });

  it('comments, replies, mentions and their counters', async () => {
    const p = await post(ada, { text: 'discuss', audience: 'PUBLIC' });
    const top = (await h.http().post(`${api}/posts/${p.id}/comments`).set(chi.auth).send({ text: 'first! @bola' }).expect(201)).body;
    const reply = (await h.http().post(`${api}/comments/${top.id}/replies`).set(ada.auth).send({ text: 'thanks' }).expect(201)).body;
    await h.http().post(`${api}/comments/${reply.id}/replies`).set(chi.auth).send({ text: 'nested' }).expect(201);

    const list = await h.http().get(`${api}/posts/${p.id}/comments`).set(bola.auth).expect(200);
    expect(list.body.items).toHaveLength(1);
    expect(list.body.items[0]).toMatchObject({ id: top.id, counts: { replies: 2 } });
    const replies = await h.http().get(`${api}/comments/${top.id}/replies`).set(bola.auth).expect(200);
    expect(replies.body.items.map((r: { text: string }) => r.text)).toEqual(['thanks', 'nested']);
    expect((await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } })).commentCount).toBe(3);
    expect(await h.prisma.notification.count({ where: { recipientId: bola.id, type: 'MENTION' } })).toBe(1);
    expect(await h.prisma.notification.count({ where: { recipientId: chi.id, type: 'COMMENT_REPLY' } })).toBe(1);

    await h.http().patch(`${api}/comments/${top.id}`).set(bola.auth).send({ text: 'hijack' }).expect(404);
    await h.http().delete(`${api}/comments/${top.id}`).set(chi.auth).expect(204);
    const after = await h.http().get(`${api}/posts/${p.id}/comments`).set(bola.auth).expect(200);
    expect(after.body.items[0]).toMatchObject({ id: top.id, deleted: true, text: null, author: null });
    expect((await h.prisma.post.findUniqueOrThrow({ where: { id: p.id } })).commentCount).toBe(2);
  });

  it('reposts: only public posts, once per user, undoable', async () => {
    const pub = await post(ada, { text: 'share me', audience: 'PUBLIC' });
    const contactsOnly = await post(ada, { text: 'contacts only' });
    await h.http().post(`${api}/posts/${contactsOnly.id}/repost`).set(bola.auth).expect(403);
    const repost = (await h.http().post(`${api}/posts/${pub.id}/repost`).set(chi.auth).expect(201)).body;
    expect(repost).toMatchObject({ kind: 'repost', repostOf: { id: pub.id } });
    await h.http().post(`${api}/posts/${pub.id}/repost`).set(chi.auth).expect(409);
    expect((await h.prisma.post.findUniqueOrThrow({ where: { id: pub.id } })).repostCount).toBe(1);
    await h.http().delete(`${api}/posts/${pub.id}/repost`).set(chi.auth).expect(204);
    expect((await h.prisma.post.findUniqueOrThrow({ where: { id: pub.id } })).repostCount).toBe(0);
    await h.http().post(`${api}/posts/${pub.id}/repost`).set(chi.auth).expect(201);
  });

  it('only the author edits; deleting removes the post from feeds and fixes counters', async () => {
    const p = await post(ada, { text: 'temporary #gone', audience: 'PUBLIC' });
    await h.drain();
    await h.http().patch(`${api}/posts/${p.id}`).set(chi.auth).send({ text: 'hacked' }).expect(404);
    const edited = await h.http().patch(`${api}/posts/${p.id}`).set(ada.auth).send({ text: 'edited #still' }).expect(200);
    expect(edited.body).toMatchObject({ text: 'edited #still', hashtags: ['still'] });
    expect((await h.prisma.hashtag.findUniqueOrThrow({ where: { tag: 'gone' } })).postCount).toBe(0);

    const before = (await h.prisma.userProfile.findUniqueOrThrow({ where: { userId: ada.id } })).postsCount;
    await h.http().delete(`${api}/posts/${p.id}`).set(chi.auth).expect(404);
    await h.http().delete(`${api}/posts/${p.id}`).set(ada.auth).expect(204);
    await h.drain();
    expect(await feedIds(chi)).not.toContain(p.id);
    expect(await h.prisma.feedEntry.count({ where: { postId: p.id } })).toBe(0);
    expect((await h.prisma.userProfile.findUniqueOrThrow({ where: { userId: ada.id } })).postsCount).toBe(before - 1);
  });

  it('blocking severs follows both ways, clears feeds and hides content', async () => {
    const p = await post(ada, { text: 'before block', audience: 'PUBLIC' });
    await h.drain();
    expect(await feedIds(chi)).toContain(p.id);
    await h.http().post(`${api}/users/${chi.id}/block`).set(ada.auth).expect(204);
    await h.drain();
    expect(await feedIds(chi)).not.toContain(p.id);
    await h.http().get(`${api}/posts/${p.id}`).set(chi.auth).expect(404);
    await h.http().get(`${api}/users/ada`).set(chi.auth).expect(404);
    await h.http().post(`${api}/users/${ada.id}/follow`).set(chi.auth).expect(404);
    await h.http().post(`${api}/posts/${p.id}/like`).set(chi.auth).expect(404);
    const ada_ = await h.prisma.userProfile.findUniqueOrThrow({ where: { userId: ada.id } });
    expect(ada_.followersCount).toBe(0);
    const blocked = await h.http().get(`${api}/users/me/blocked`).set(ada.auth).expect(200);
    expect(blocked.body.items.map((u: { id: string }) => u.id)).toEqual([chi.id]);
    await h.http().delete(`${api}/users/${chi.id}/block`).set(ada.auth).expect(204);
  });

  it('discover recommends public posts from unconnected accounts and suggestions exclude connections', async () => {
    const p = await post(eze, { text: 'hello world #discover', audience: 'PUBLIC' });
    await post(eze, { text: 'contacts only' });
    const discover = await h.http().get(`${api}/feed/discover`).set(bola.auth).expect(200);
    const ids = discover.body.items.map((x: { id: string }) => x.id);
    expect(ids).toContain(p.id);
    expect(discover.body.items.every((x: { audience: string }) => x.audience === 'PUBLIC')).toBe(true);

    const suggestions = await h.http().get(`${api}/users/me/suggestions`).set(chi.auth).expect(200);
    const suggested = suggestions.body.map((s: { id: string }) => s.id);
    expect(suggested).not.toContain(chi.id);
    expect(suggested).not.toContain(dami.id); // already followed
  });

  it('paginates feeds with an opaque cursor without duplicates', async () => {
    for (let i = 0; i < 7; i++) await post(bola, { text: `page ${i}`, audience: 'PUBLIC' });
    await h.drain();
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const res: { body: { items: Array<{ id: string }>; nextCursor: string | null } } = await h.http()
        .get(`${api}/feed/following`).query(cursor ? { limit: 3, cursor } : { limit: 3 }).set(bola.auth).expect(200);
      seen.push(...res.body.items.map((x) => x.id));
      cursor = res.body.nextCursor;
    } while (cursor);
    expect(new Set(seen).size).toBe(seen.length);
    expect(seen.length).toBe(await h.prisma.feedEntry.count({ where: { userId: bola.id, post: { deletedAt: null } } }));
    await h.http().get(`${api}/feed/following?cursor=garbage`).set(bola.auth).expect(400);
  });
});
