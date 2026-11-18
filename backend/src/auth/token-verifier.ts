import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { Auth, getAuth } from 'firebase-admin/auth';
import type { Env } from '../config/env';
import { AppError } from '../common/errors/app-error';

/** Claims the backend relies on, taken only from a verified Firebase ID token. */
export interface VerifiedToken {
  uid: string;
  email?: string;
  emailVerified: boolean;
  /** Present only when the user signed in with Firebase phone auth, i.e. the number is verified. */
  phoneNumber?: string;
  name?: string;
  signInProvider?: string;
  /** Token expiry; long-lived connections (WebSocket) must re-authenticate before it. */
  expiresAt: Date;
}

export abstract class TokenVerifier {
  abstract verify(idToken: string, checkRevoked: boolean): Promise<VerifiedToken>;
  /** Deletes the Firebase Auth user (account-deletion workflow). */
  abstract deleteUser(uid: string): Promise<void>;
  /** Invalidates every session of the user (suspension). */
  abstract revokeSessions(uid: string): Promise<void>;
}

/** The one Firebase Admin app (Auth + Messaging). Credentials come from env and never leave the server. */
export function firebaseApp(config: ConfigService<Env, true>): App {
  const existing = getApps().find((a) => a.name === 'mybuddy');
  if (existing) return existing;
  const projectId = config.get('FIREBASE_PROJECT_ID', { infer: true });
  const clientEmail = config.get('FIREBASE_CLIENT_EMAIL', { infer: true });
  // Env files store the PEM with literal "\n".
  const privateKey = config.get('FIREBASE_PRIVATE_KEY', { infer: true })?.replace(/\\n/g, '\n');
  if (clientEmail && privateKey && projectId) {
    return initializeApp({ credential: cert({ projectId, clientEmail, privateKey }), projectId }, 'mybuddy');
  }
  // Development against the Auth emulator (FIREBASE_AUTH_EMULATOR_HOST) needs only a project id.
  if (config.get('FIREBASE_AUTH_EMULATOR_HOST', { infer: true })) {
    return initializeApp({ projectId: projectId ?? 'demo-mybuddy' }, 'mybuddy');
  }
  throw new Error('Firebase Admin is not configured: set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY');
}

/** Firebase Admin SDK implementation. Credentials are server-side only (env), never sent to clients. */
@Injectable()
export class FirebaseTokenVerifier extends TokenVerifier {
  private readonly logger = new Logger(FirebaseTokenVerifier.name);
  private readonly auth: Auth;

  constructor(config: ConfigService<Env, true>) {
    super();
    this.auth = getAuth(firebaseApp(config));
  }

  async verify(idToken: string, checkRevoked: boolean): Promise<VerifiedToken> {
    try {
      const t = await this.auth.verifyIdToken(idToken, checkRevoked);
      return {
        uid: t.uid,
        email: t.email,
        emailVerified: t.email_verified === true,
        phoneNumber: t.phone_number,
        name: typeof t.name === 'string' ? t.name : undefined,
        signInProvider: t.firebase?.sign_in_provider,
        expiresAt: new Date(t.exp * 1000),
      };
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === 'auth/id-token-revoked' || code === 'auth/user-disabled') {
        throw AppError.unauthenticated('Session has been revoked, sign in again', 'TOKEN_REVOKED');
      }
      if (code !== 'auth/id-token-expired' && code !== 'auth/argument-error') {
        this.logger.warn(`ID token rejected: ${code ?? 'unknown'}`);
      }
      throw AppError.unauthenticated('Invalid or expired token');
    }
  }

  async deleteUser(uid: string): Promise<void> {
    try {
      await this.auth.deleteUser(uid);
    } catch (error) {
      if ((error as { code?: string }).code === 'auth/user-not-found') return; // already gone: idempotent
      throw error;
    }
  }

  async revokeSessions(uid: string): Promise<void> {
    await this.auth.revokeRefreshTokens(uid);
  }
}
