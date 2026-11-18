// Firestore rules tests. NOT RUN by the author (no Node/emulator access when written).
// Usage:  cd firebase/rules-tests && npm install && npm test
// (needs the Firebase CLI; `npm test` starts the Firestore emulator, runs these, and stops it)
const { test, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } = require('firebase/firestore');

let env;

before(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
  env = await initializeTestEnvironment({
    projectId: 'mybuddy-rules-test',
    firestore: {
      host, port: Number(port),
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules.proposed'), 'utf8'),
    },
  });
});

after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { email: 'a@x.com', displayName: 'Alice', phoneNumber: 100 });
    await setDoc(doc(db, 'users/bob'), { email: 'b@x.com', displayName: 'Bob', phoneNumber: 200 });
    await setDoc(doc(db, 'chats/c1'), { participants: ['alice', 'bob'], lastMessage: '' });
    await setDoc(doc(db, 'chats/c1/messages/m1'), {
      senderId: 'alice', recipientId: 'bob', content: 'hi', timestamp: new Date(), seen: false, sent: true,
    });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();
const msg = (extra = {}) => ({
  senderId: 'alice', recipientId: 'bob', content: 'hello', timestamp: serverTimestamp(), seen: false, sent: true, ...extra,
});

// ---- users
test('signed-out users cannot read profiles', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice')));
});
test('users can read others but write only their own profile', async () => {
  await assertSucceeds(getDoc(doc(as('alice'), 'users/bob')));
  await assertSucceeds(updateDoc(doc(as('alice'), 'users/alice'), { displayName: 'A' }));
  await assertFails(updateDoc(doc(as('alice'), 'users/bob'), { displayName: 'hacked' }));
  await assertFails(deleteDoc(doc(as('alice'), 'users/alice')));
});

// ---- chats and messages
test('participants read the chat, outsiders do not', async () => {
  await assertSucceeds(getDoc(doc(as('bob'), 'chats/c1')));
  await assertFails(getDoc(doc(as('mallory'), 'chats/c1')));
});
test('participant can send; sender id cannot be spoofed; outsiders cannot send', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'chats/c1/messages/m2'), msg()));
  await assertFails(setDoc(doc(as('alice'), 'chats/c1/messages/m3'), msg({ senderId: 'bob', recipientId: 'alice' })));
  await assertFails(setDoc(doc(as('mallory'), 'chats/c1/messages/m4'), msg({ senderId: 'mallory' })));
});
test('outsiders cannot read messages', async () => {
  await assertSucceeds(getDoc(doc(as('bob'), 'chats/c1/messages/m1')));
  await assertFails(getDoc(doc(as('mallory'), 'chats/c1/messages/m1')));
});
test('sender retry of the same message id (idempotent resend) is allowed', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'chats/c1/messages/m1'), msg({ content: 'hi' })));
});
test('sender cannot rewrite message content', async () => {
  await assertFails(setDoc(doc(as('alice'), 'chats/c1/messages/m1'), msg({ content: 'edited' })));
});
test('recipient may only flip seen', async () => {
  await assertSucceeds(updateDoc(doc(as('bob'), 'chats/c1/messages/m1'), { seen: true }));
  await assertFails(updateDoc(doc(as('bob'), 'chats/c1/messages/m1'), { content: 'forged' }));
});
test('only the sender may delete a message', async () => {
  await assertFails(deleteDoc(doc(as('bob'), 'chats/c1/messages/m1')));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'chats/c1/messages/m1')));
});
test('a blocked sender cannot message the blocker', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/bob/blocks/alice'), { phoneNumber: 100 });
  });
  await assertFails(setDoc(doc(as('alice'), 'chats/c1/messages/m5'), msg()));
  await assertSucceeds(setDoc(doc(as('bob'), 'chats/c1/messages/m6'), msg({ senderId: 'bob', recipientId: 'alice' })));
});
test('block lists are private to their owner', async () => {
  await assertSucceeds(setDoc(doc(as('bob'), 'users/bob/blocks/alice'), { phoneNumber: 100 }));
  await assertFails(getDoc(doc(as('alice'), 'users/bob/blocks/alice')));
  await assertFails(setDoc(doc(as('alice'), 'users/bob/blocks/mallory'), { phoneNumber: 1 }));
});

// ---- reports, devices
test('reports are create-only and cannot be filed as someone else', async () => {
  const r = { reporterId: 'alice', targetUserId: 'bob', reason: 'spam', status: 'open' };
  await assertSucceeds(setDoc(doc(as('alice'), 'reports/r1'), r));
  await assertFails(setDoc(doc(as('alice'), 'reports/r2'), { ...r, reporterId: 'bob' }));
  await assertFails(setDoc(doc(as('alice'), 'reports/r3'), { ...r, reason: 'made-up' }));
  await assertFails(getDoc(doc(as('alice'), 'reports/r1')));
});
test('push tokens are owner-only', async () => {
  await assertSucceeds(setDoc(doc(as('bob'), 'users/bob/devices/d1'), { token: 't' }));
  await assertFails(setDoc(doc(as('alice'), 'users/bob/devices/d2'), { token: 'x' }));
  await assertFails(getDoc(doc(as('alice'), 'users/bob/devices/d1')));
});

// ---- feed and reactions
test('feed copies: author must be the caller; only the owner reads their feed', async () => {
  const post = (author) => ({ content: 'p', feedOwnerId: author, timestamp: serverTimestamp(), likes: 0, dislikes: 0 });
  await assertSucceeds(setDoc(doc(as('alice'), 'user_feed/200/posts/p1'), post('100')));
  await assertFails(setDoc(doc(as('alice'), 'user_feed/200/posts/p2'), post('200')));
  await assertSucceeds(getDoc(doc(as('bob'), 'user_feed/200/posts/p1')));
  await assertFails(getDoc(doc(as('alice'), 'user_feed/200/posts/p1')));
});
test('republishing the same post id by the same author is allowed', async () => {
  const post = { content: 'p', feedOwnerId: '100', timestamp: serverTimestamp(), likes: 0, dislikes: 0 };
  await assertSucceeds(setDoc(doc(as('alice'), 'user_feed/200/posts/p1'), post));
  await assertSucceeds(setDoc(doc(as('alice'), 'user_feed/200/posts/p1'), post));
});
test('reactions: one per user, own document only, valid type only', async () => {
  await assertSucceeds(setDoc(doc(as('alice'), 'post_reactions/p1/users/alice'), { type: 'like' }));
  await assertFails(setDoc(doc(as('alice'), 'post_reactions/p1/users/bob'), { type: 'like' }));
  await assertFails(setDoc(doc(as('alice'), 'post_reactions/p1/users/alice'), { type: 'love' }));
  await assertSucceeds(deleteDoc(doc(as('alice'), 'post_reactions/p1/users/alice')));
});
