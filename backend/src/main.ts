import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { buildOpenApi, configureApp } from './bootstrap';
import { Env, NodeEnv } from './config/env';
import { RedisIoAdapter } from './realtime/redis-io.adapter';
import { mountQueueDashboard } from './queues/dashboard';

async function main() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: true });
  app.set('trust proxy', 1); // behind one load balancer: req.ip is the client address
  app.useBodyParser('json', { limit: '256kb' });
  configureApp(app);

  const config = app.get(ConfigService<Env, true>);
  const io = new RedisIoAdapter(app, config.get('REDIS_URL', { infer: true }));
  io.connect();
  app.useWebSocketAdapter(io);
  if (config.get('ENABLE_QUEUE_DASHBOARD', { infer: true }) === 'true') {
    mountQueueDashboard(app, config.get('QUEUE_DASHBOARD_PASSWORD', { infer: true }));
  }
  if (config.get('NODE_ENV', { infer: true }) !== NodeEnv.production) {
    SwaggerModule.setup('docs', app, buildOpenApi(app));
  }
  await app.listen(config.get('PORT', { infer: true }), '0.0.0.0');
}

void main();
