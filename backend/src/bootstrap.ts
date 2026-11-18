import { INestApplication, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DocumentBuilder, OpenAPIObject, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { Logger } from 'nestjs-pino';
import { HttpExceptionFilter } from './common/errors/http-exception.filter';
import type { Env } from './config/env';

export const API_PREFIX = 'api/v1';

/** Applied identically by main.ts and the integration tests, so tests exercise the real HTTP stack. */
export function configureApp(app: INestApplication): void {
  const config = app.get(ConfigService<Env, true>);
  app.useLogger(app.get(Logger));
  app.setGlobalPrefix(API_PREFIX, { exclude: ['health/live', 'health/ready'] });
  app.use(helmet());
  const origins = config.get('CORS_ORIGINS', { infer: true })?.split(',').map((o) => o.trim()).filter(Boolean);
  // Bearer tokens, no cookies: CSRF does not apply, and CORS is closed unless origins are configured.
  app.enableCors({ origin: origins?.length ? origins : false, credentials: false });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, // strip unknown properties (no mass assignment of protected fields)
      forbidNonWhitelisted: true,
      transform: true,
      transformOptions: { enableImplicitConversion: false },
    }),
  );
  app.useGlobalFilters(new HttpExceptionFilter());
  app.enableShutdownHooks();
}

export function buildOpenApi(app: INestApplication): OpenAPIObject {
  const doc = new DocumentBuilder()
    .setTitle('MyBuddy API')
    .setDescription('REST API for the MyBuddy iOS app. Authenticate with a Firebase ID token: `Authorization: Bearer <token>`. Real-time events use Socket.IO at `/realtime` (see docs/backend/REALTIME.md).')
    .setVersion('1.0')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'Firebase ID token' })
    .build();
  return SwaggerModule.createDocument(app, doc);
}
