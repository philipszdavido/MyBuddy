import { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { Server, ServerOptions } from 'socket.io';
import { createRedis } from '../redis/redis.module';

/** Socket.IO with the Redis adapter, so rooms and fetchSockets() span every API instance. */
export class RedisIoAdapter extends IoAdapter {
  private adapter?: ReturnType<typeof createAdapter>;

  constructor(app: INestApplicationContext, private readonly redisUrl: string) {
    super(app);
  }

  connect(): void {
    const pub = createRedis(this.redisUrl);
    const sub = pub.duplicate();
    this.adapter = createAdapter(pub, sub);
  }

  override createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, options) as Server;
    if (this.adapter) server.adapter(this.adapter);
    return server;
  }
}
