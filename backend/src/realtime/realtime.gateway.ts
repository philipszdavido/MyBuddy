import { Inject, Logger, OnModuleDestroy } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { plainToInstance } from 'class-transformer';
import { ArrayMaxSize, IsArray, IsBoolean, IsInt, IsOptional, IsString, IsUUID, MaxLength, Min, validate } from 'class-validator';
import type Redis from 'ioredis';
import type { Namespace, Socket } from 'socket.io';
import { TokenVerifier } from '../auth/token-verifier';
import { UserProvisioningService } from '../auth/user-provisioning.service';
import { toErrorBody } from '../common/errors/http-exception.filter';
import { RelationshipService } from '../graph/relationship.service';
import { MessagingService } from '../messaging/messaging.service';
import { REDIS } from '../redis/redis.module';
import { PresenceService } from './presence.service';
import { REALTIME_CHANNEL, RealtimeEnvelope } from './realtime.publisher';

class SendDto {
  @IsUUID() conversationId: string;
  @IsString() @MaxLength(64) clientId: string;
  @IsOptional() @IsString() @MaxLength(4000) text?: string;
  @IsOptional() @IsArray() @ArrayMaxSize(10) @IsUUID('4', { each: true }) mediaIds?: string[];
  @IsOptional() @IsUUID() replyToId?: string;
}
class TypingDto {
  @IsUUID() conversationId: string;
  @IsBoolean() isTyping: boolean;
}
class SeqDto {
  @IsUUID() conversationId: string;
  @IsInt() @Min(0) seq: number;
}
class PresenceDto {
  @IsArray() @ArrayMaxSize(100) @IsUUID('4', { each: true }) userIds: string[];
}
class RefreshDto {
  @IsString() token: string;
}

type Ack<T = unknown> = { ok: true; data?: T } | { ok: false; error: { code: string; message: string } };

interface SocketData {
  userId: string;
  firebaseUid: string;
  expiryTimer?: NodeJS.Timeout;
  tokens: number;
  refilledAt: number;
}

const EVENTS_PER_SECOND = 10;
const BURST = 30;
const EXPIRY_GRACE_MS = 60_000;

/**
 * Socket.IO gateway at namespace /realtime.
 *  - Auth: Firebase ID token in the handshake (`auth: { token }`), verified like REST; sockets whose
 *    token expires are disconnected unless the client sends `auth:refresh` with a new token.
 *  - Each socket joins only `user:{id}` (and `presence:{id}` rooms it is allowed to watch). There are no
 *    conversation rooms to join: every event is membership-checked against PostgreSQL, so a client can
 *    never subscribe to a conversation it is not in.
 *  - Outbound events arrive via Redis pub/sub (RealtimePublisher) and are emitted to *local* sockets only,
 *    so horizontal scaling delivers each event once. The Socket.IO Redis adapter is also installed (main.ts)
 *    for cluster-wide operations.
 *  - Per-socket token-bucket rate limit; message sends are additionally limited per user in MessagingService.
 */
@WebSocketGateway({ namespace: '/realtime', transports: ['websocket'], cors: { origin: false }, pingInterval: 25_000, pingTimeout: 20_000, maxHttpBufferSize: 64 * 1024 })
export class RealtimeGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect, OnModuleDestroy {
  @WebSocketServer() private readonly server: Namespace;
  private readonly logger = new Logger(RealtimeGateway.name);
  private subscriber?: Redis;

  constructor(
    private readonly verifier: TokenVerifier,
    private readonly provisioning: UserProvisioningService,
    private readonly messaging: MessagingService,
    private readonly presence: PresenceService,
    private readonly relationships: RelationshipService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  afterInit() {
    this.subscriber = this.redis.duplicate();
    void this.subscriber.subscribe(REALTIME_CHANNEL);
    this.subscriber.on('message', (_channel: string, raw: string) => {
      try {
        const env = JSON.parse(raw) as RealtimeEnvelope;
        const rooms = [...(env.userIds ?? []).map((id) => `user:${id}`), ...(env.rooms ?? [])];
        if (!rooms.length) return;
        this.server.local.to(rooms).emit(env.event, env.payload);
        if (env.event === 'session:revoked') this.server.local.in(rooms).disconnectSockets(true);
      } catch (error) {
        this.logger.warn(`bad realtime envelope: ${String(error)}`);
      }
    });
  }

  async onModuleDestroy() {
    await this.subscriber?.quit().catch(() => undefined);
  }

  async handleConnection(socket: Socket) {
    try {
      const token = (socket.handshake.auth as { token?: unknown })?.token;
      if (typeof token !== 'string') throw new Error('missing token');
      const verified = await this.verifier.verify(token, false);
      const user = await this.provisioning.resolve(verified);
      if (user.status !== 'ACTIVE') throw new Error('inactive account');
      const data: SocketData = { userId: user.id, firebaseUid: verified.uid, tokens: BURST, refilledAt: Date.now() };
      socket.data = data;
      this.scheduleExpiry(socket, verified.expiresAt);
      await socket.join(`user:${user.id}`);
      await this.presence.connect(user.id, socket.id);
      socket.emit('ready', { userId: user.id });
    } catch {
      socket.emit('error', { code: 'UNAUTHENTICATED', message: 'Invalid or expired token' });
      socket.disconnect(true);
    }
  }

  async handleDisconnect(socket: Socket) {
    const data = socket.data as SocketData | undefined;
    if (!data?.userId) return;
    clearTimeout(data.expiryTimer);
    await this.presence.disconnect(data.userId, socket.id).catch(() => undefined);
  }

  @SubscribeMessage('auth:refresh')
  async refresh(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, RefreshDto, body, async (dto, data) => {
      const verified = await this.verifier.verify(dto.token, false);
      if (verified.uid !== data.firebaseUid) throw new Error('token belongs to another user');
      this.scheduleExpiry(socket, verified.expiresAt);
      return undefined;
    });
  }

  @SubscribeMessage('message:send')
  async send(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, SendDto, body, (dto, data) =>
      this.messaging.send(data.userId, dto.conversationId, { clientId: dto.clientId, text: dto.text, mediaIds: dto.mediaIds, replyToId: dto.replyToId }));
  }

  @SubscribeMessage('typing')
  async typing(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, TypingDto, body, (dto, data) => this.messaging.typing(data.userId, dto.conversationId, dto.isTyping));
  }

  @SubscribeMessage('conversation:read')
  async read(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, SeqDto, body, (dto, data) => this.messaging.markRead(data.userId, dto.conversationId, dto.seq));
  }

  @SubscribeMessage('conversation:delivered')
  async delivered(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, SeqDto, body, (dto, data) => this.messaging.markDelivered(data.userId, dto.conversationId, dto.seq));
  }

  @SubscribeMessage('presence:subscribe')
  async presenceSubscribe(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, PresenceDto, body, async (dto, data) => {
      const rels = await this.relationships.many(data.userId, dto.userIds);
      const allowed = dto.userIds.filter((id) => id !== data.userId && !rels.get(id)?.blocking && !rels.get(id)?.blockedBy);
      await socket.join(allowed.map((id) => `presence:${id}`));
      return this.presence.views(allowed);
    });
  }

  @SubscribeMessage('presence:unsubscribe')
  async presenceUnsubscribe(@ConnectedSocket() socket: Socket, @MessageBody() body: unknown): Promise<Ack> {
    return this.handle(socket, PresenceDto, body, async (dto) => {
      for (const id of dto.userIds) await socket.leave(`presence:${id}`);
      return undefined;
    });
  }

  @SubscribeMessage('heartbeat')
  async heartbeat(@ConnectedSocket() socket: Socket): Promise<Ack> {
    return this.handle(socket, null, undefined, async (_dto, data) => {
      await this.presence.touch(data.userId, socket.id);
      return undefined;
    });
  }

  /** Validation, auth state, rate limiting and error mapping shared by every event. */
  private async handle<D extends object, R>(
    socket: Socket,
    dtoClass: (new () => D) | null,
    body: unknown,
    fn: (dto: D, data: SocketData) => Promise<R>,
  ): Promise<Ack<R>> {
    const data = socket.data as SocketData | undefined;
    if (!data?.userId) return { ok: false, error: { code: 'UNAUTHENTICATED', message: 'Not authenticated' } };
    if (!this.take(data)) return { ok: false, error: { code: 'RATE_LIMITED', message: 'Too many events' } };
    let dto = {} as D;
    if (dtoClass) {
      dto = plainToInstance(dtoClass, body ?? {});
      const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
      if (errors.length) return { ok: false, error: { code: 'VALIDATION_FAILED', message: 'Invalid payload' } };
    }
    try {
      return { ok: true, data: await fn(dto, data) };
    } catch (error) {
      const { status, body: err } = toErrorBody(error);
      if (status >= 500) this.logger.error({ err: error }, 'realtime handler failed');
      return { ok: false, error: { code: err.error.code, message: err.error.message } };
    }
  }

  private take(data: SocketData): boolean {
    const now = Date.now();
    data.tokens = Math.min(BURST, data.tokens + ((now - data.refilledAt) / 1000) * EVENTS_PER_SECOND);
    data.refilledAt = now;
    if (data.tokens < 1) return false;
    data.tokens -= 1;
    return true;
  }

  private scheduleExpiry(socket: Socket, expiresAt: Date) {
    const data = socket.data as SocketData;
    clearTimeout(data.expiryTimer);
    const ms = Math.max(0, expiresAt.getTime() - Date.now()) + EXPIRY_GRACE_MS;
    data.expiryTimer = setTimeout(() => {
      socket.emit('error', { code: 'TOKEN_EXPIRED', message: 'Reconnect with a fresh token' });
      socket.disconnect(true);
    }, Math.min(ms, 2 ** 31 - 1));
  }
}
