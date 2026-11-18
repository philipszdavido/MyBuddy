import { Controller, Get, Inject, Module } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { HealthCheck, HealthCheckService, HealthIndicatorService, TerminusModule } from '@nestjs/terminus';
import type Redis from 'ioredis';
import { Public } from '../common/decorators/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { REDIS } from '../redis/redis.module';

@ApiTags('health')
@Public()
@Controller('health')
export class HealthController {
  constructor(
    private readonly health: HealthCheckService,
    private readonly indicator: HealthIndicatorService,
    private readonly prisma: PrismaService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  /** Liveness: the process is up. Never touches dependencies, so a DB outage does not restart pods. */
  @Get('live')
  live() {
    return { status: 'ok' };
  }

  /** Readiness: dependencies reachable; load balancers stop routing traffic when this fails. */
  @Get('ready')
  @HealthCheck()
  ready() {
    return this.health.check([
      async () => {
        const i = this.indicator.check('postgres');
        try {
          await this.prisma.$queryRaw`SELECT 1`;
          return i.up();
        } catch {
          return i.down();
        }
      },
      async () => {
        const i = this.indicator.check('redis');
        try {
          return (await this.redis.ping()) === 'PONG' ? i.up() : i.down();
        } catch {
          return i.down();
        }
      },
    ]);
  }
}

@Module({ imports: [TerminusModule], controllers: [HealthController] })
export class HealthModule {}
