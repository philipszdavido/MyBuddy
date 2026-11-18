import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter } from '@bull-board/express';
import { INestApplication } from '@nestjs/common';
import { getQueueToken } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type { NextFunction, Request, Response } from 'express';
import { timingSafeEqual } from 'node:crypto';
import { Q } from './queues';

const PATH = '/admin/queues';

/**
 * Job monitoring (Bull Board): queue depths, failed jobs with stack traces, retry/remove.
 * Mounted only when ENABLE_QUEUE_DASHBOARD=true and QUEUE_DASHBOARD_PASSWORD is set; protected with
 * HTTP basic auth (user "admin"). Keep it behind the internal network / VPN in production as well.
 */
export function mountQueueDashboard(app: INestApplication, password: string | undefined): boolean {
  if (!password) return false;
  const adapter = new ExpressAdapter();
  adapter.setBasePath(PATH);
  createBullBoard({ queues: Object.values(Q).map((name) => new BullMQAdapter(app.get<Queue>(getQueueToken(name)))), serverAdapter: adapter });
  const expected = Buffer.from(`admin:${password}`);
  const guard = (req: Request, res: Response, next: NextFunction) => {
    const header = req.headers.authorization ?? '';
    const given = Buffer.from(header.startsWith('Basic ') ? Buffer.from(header.slice(6), 'base64').toString('utf8') : '');
    if (given.length === expected.length && timingSafeEqual(given, expected)) return next();
    res.setHeader('WWW-Authenticate', 'Basic realm="queues"').status(401).end();
  };
  app.use(PATH, guard, adapter.getRouter());
  return true;
}
