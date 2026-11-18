import { NestFactory } from '@nestjs/core';
import { writeFileSync } from 'node:fs';
import { AppModule } from '../app.module';
import { buildOpenApi, configureApp } from '../bootstrap';

/** Writes openapi.json (checked in, consumed by the iOS client). Needs DATABASE_URL/REDIS_URL reachable. */
async function main() {
  const app = await NestFactory.create(AppModule, { logger: false });
  configureApp(app);
  await app.init();
  const out = process.argv[2] ?? 'openapi.json';
  writeFileSync(out, JSON.stringify(buildOpenApi(app), null, 2) + '\n');
  await app.close();
  console.log(`wrote ${out}`);
}

void main();
