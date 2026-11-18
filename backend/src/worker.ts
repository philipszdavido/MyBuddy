import { NestFactory } from '@nestjs/core';
import { Logger } from 'nestjs-pino';
import { WorkerModule } from './worker.module';

/**
 * Background worker process (no HTTP). Scale it independently of the API. On SIGTERM, Nest's shutdown
 * hooks close every BullMQ worker, which waits for in-flight jobs to finish before exiting
 * (give the container a stop grace period longer than the slowest job, e.g. video transcoding).
 */
async function main() {
  const app = await NestFactory.createApplicationContext(WorkerModule, { bufferLogs: true });
  app.useLogger(app.get(Logger));
  app.enableShutdownHooks();
  app.get(Logger).log('worker started');
}

void main();
