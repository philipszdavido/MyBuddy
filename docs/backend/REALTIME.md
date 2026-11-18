# Real-time protocol (Socket.IO)

Namespace `/realtime` on the API host (`wss://<api>/socket.io/?EIO=4&transport=websocket`).
Socket.IO v4 server; the iOS app uses its own minimal client (`ios/MyBuddy/Data/API/RealtimeClient.swift`).

**Real-time delivery is best-effort; PostgreSQL is the source of truth.** After every (re)connect a
client re-syncs over REST: `GET /conversations` and, per open conversation,
`GET /conversations/:id/messages?afterSeq=<highest seq you have>`. Every message has a per-conversation,
gap-free `seq`; a gap in received `seq`s means "catch up via REST".

## Connecting
- Handshake: `auth: { token: <Firebase ID token> }`. On success the server emits `ready { userId }`.
  An invalid token produces `error { code: "UNAUTHENTICATED" }` and a disconnect.
- Tokens expire after ~1 h. Send `auth:refresh { token }` before then; otherwise the server emits
  `error { code: "TOKEN_EXPIRED" }` and disconnects 60 s after expiry.
- Sockets join only their own user room. There are no conversation rooms: every event is checked
  against conversation membership in PostgreSQL.
- Rate limit: about 10 events/s per socket (burst 30); message sends are also limited per user.
- Suspension or account deletion: the server emits `session:revoked` and disconnects.

## Client → server (all acknowledged: `{ ok: true, data }` or `{ ok: false, error: { code, message } }`)
| Event | Payload | Ack data |
|---|---|---|
| `message:send` | `{ conversationId, clientId, text?, mediaIds?, replyToId? }` | the persisted message |
| `typing` | `{ conversationId, isTyping }` | – |
| `conversation:read` | `{ conversationId, seq }` | `{ lastReadSeq }` |
| `conversation:delivered` | `{ conversationId, seq }` | `{ lastDeliveredSeq }` |
| `presence:subscribe` / `presence:unsubscribe` | `{ userIds: [...≤100] }` | presence of allowed users |
| `heartbeat` | – | – (keeps presence alive; send every ~25 s) |
| `auth:refresh` | `{ token }` | – |

`clientId` makes sends idempotent: resending the same `clientId` (after a lost ack) returns the same
message and never duplicates it. The REST endpoint `POST /conversations/:id/messages` is equivalent.

## Server → client
| Event | Payload |
|---|---|
| `message:new`, `message:updated` | message view (same shape as REST) |
| `message:deleted` | `{ conversationId, messageId, seq }` |
| `message:reaction` | `{ conversationId, messageId, reactions: [{ emoji, userId }] }` |
| `conversation:updated` | `{ conversationId }` (members/title changed; refetch) |
| `conversation:read` / `conversation:delivered` | `{ conversationId, userId, seq }` (receipts are watermarks; hidden when the reader disabled read receipts) |
| `typing` | `{ conversationId, userId, isTyping }` |
| `presence` | `{ userId, online, lastSeenAt }` (only for subscribed, non-blocked users who share activity status) |
| `notification:new` | activity-inbox item |
| `media:updated` | `{ mediaId, status }` when processing finishes or fails |

## Scaling
Events are published to the Redis channel `rt:events`; every API instance emits to its **local**
sockets only, so each socket receives an event exactly once however many instances run. The Socket.IO
Redis adapter is also installed for cluster-wide operations (disconnecting a user's sockets everywhere).
Workers publish through the same channel. Load balancers need WebSocket upgrade support; sticky sessions
are not required with the WebSocket-only transport.
