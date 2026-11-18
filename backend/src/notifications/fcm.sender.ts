import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { getMessaging, Messaging } from 'firebase-admin/messaging';
import type { Env } from '../config/env';
import { firebaseApp } from '../auth/token-verifier';

export interface PushMessage {
  title: string;
  body: string;
  /** String-only map (FCM requirement). Always includes `deepLink`. */
  data: Record<string, string>;
  /** iOS: groups notifications (e.g. per conversation). */
  threadId?: string;
  badge?: number;
  /** FCM collapse key / apns-collapse-id: a newer push with the same key replaces the old one. */
  collapseKey?: string;
}

export interface PushResult {
  token: string;
  ok: boolean;
  /** Token is invalid or unregistered and must be removed. */
  invalidToken: boolean;
  error?: string;
}

export abstract class FcmSender {
  abstract send(tokens: string[], message: PushMessage): Promise<PushResult[]>;
}

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** Firebase Cloud Messaging via the Admin SDK (credentials server-side only). */
@Injectable()
export class FirebaseFcmSender extends FcmSender {
  private readonly messaging: Messaging;

  constructor(config: ConfigService<Env, true>) {
    super();
    this.messaging = getMessaging(firebaseApp(config));
  }

  async send(tokens: string[], m: PushMessage): Promise<PushResult[]> {
    if (tokens.length === 0) return [];
    const results: PushResult[] = [];
    for (let i = 0; i < tokens.length; i += 500) {
      const chunk = tokens.slice(i, i + 500);
      const res = await this.messaging.sendEachForMulticast({
        tokens: chunk,
        notification: { title: m.title, body: m.body },
        data: m.data,
        android: { collapseKey: m.collapseKey, priority: 'high' },
        apns: {
          headers: m.collapseKey ? { 'apns-collapse-id': m.collapseKey.slice(0, 64) } : undefined,
          payload: { aps: { sound: 'default', badge: m.badge, threadId: m.threadId, mutableContent: true } },
        },
      });
      res.responses.forEach((r, idx) => {
        const code = r.error?.code;
        results.push({ token: chunk[idx], ok: r.success, invalidToken: !!code && INVALID_TOKEN_CODES.has(code), error: code });
      });
    }
    return results;
  }
}
