import { plainToInstance, Transform } from 'class-transformer';
import { IsBooleanString, IsEnum, IsInt, IsOptional, IsString, IsUrl, Max, Min, validateSync } from 'class-validator';

export enum NodeEnv {
  development = 'development',
  test = 'test',
  staging = 'staging',
  production = 'production',
}

const toInt = ({ value }: { value: unknown }) => (value === undefined || value === '' ? undefined : Number(value));

/**
 * Every environment variable the backend reads. Validated once at boot; the process refuses to start
 * on a missing or malformed value, so misconfiguration never surfaces as a runtime 500.
 */
export class Env {
  @IsEnum(NodeEnv)
  NODE_ENV: NodeEnv = NodeEnv.development;

  @Transform(toInt) @IsInt() @Min(1) @Max(65535)
  PORT = 3000;

  @IsString()
  DATABASE_URL: string;

  @IsString()
  REDIS_URL: string;

  /** Comma-separated origins allowed by CORS. The iOS app is not a browser and does not need CORS. */
  @IsOptional() @IsString()
  CORS_ORIGINS?: string;

  // Firebase Admin. All three are required outside development/test; FIREBASE_AUTH_EMULATOR_HOST
  // (read directly by the Admin SDK) may replace them in development.
  @IsOptional() @IsString() FIREBASE_PROJECT_ID?: string;
  @IsOptional() @IsString() FIREBASE_CLIENT_EMAIL?: string;
  @IsOptional() @IsString() FIREBASE_PRIVATE_KEY?: string;
  @IsOptional() @IsString() FIREBASE_AUTH_EMULATOR_HOST?: string;

  // Cloudflare R2 (S3-compatible).
  @IsOptional() @IsString() R2_ACCOUNT_ID?: string;
  @IsOptional() @IsString() R2_ACCESS_KEY_ID?: string;
  @IsOptional() @IsString() R2_SECRET_ACCESS_KEY?: string;
  @IsOptional() @IsString() R2_BUCKET_NAME?: string;
  /** Public delivery base for processed variants (custom domain on the bucket). No trailing slash. */
  @IsOptional() @IsUrl({ require_tld: false }) R2_PUBLIC_URL?: string;
  /** Override endpoint (MinIO or the R2 jurisdiction endpoint). Defaults to https://{account}.r2.cloudflarestorage.com */
  @IsOptional() @IsUrl({ require_tld: false }) R2_ENDPOINT?: string;

  /** Authors with more followers than this are fanned out on read instead of on write. */
  @Transform(toInt) @IsInt() @Min(1)
  FEED_FANOUT_MAX_FOLLOWERS = 5000;

  @Transform(toInt) @IsInt() @Min(1)
  WORKER_CONCURRENCY = 5;

  @IsOptional() @IsBooleanString()
  ENABLE_QUEUE_DASHBOARD?: string;

  /** Basic-auth password (user "admin") for /admin/queues. Required to enable the dashboard. */
  @IsOptional() @IsString()
  QUEUE_DASHBOARD_PASSWORD?: string;

  @IsOptional() @IsString()
  LOG_LEVEL?: string;

  /** smtp(s)://user:pass@host:port for transactional email. Unset = email jobs are skipped. */
  @IsOptional() @IsString()
  SMTP_URL?: string;

  @IsOptional() @IsString()
  EMAIL_FROM?: string;
}

export function validateEnv(raw: Record<string, unknown>): Env {
  // Blank values (e.g. `R2_PUBLIC_URL=` left over from .env.example) mean "not set".
  const cleaned = Object.fromEntries(Object.entries(raw).filter(([, v]) => !(typeof v === 'string' && v.trim() === '')));
  const env = plainToInstance(Env, cleaned, { enableImplicitConversion: false, exposeDefaultValues: true });
  const errors = validateSync(env, { skipMissingProperties: false, whitelist: false });
  if (errors.length > 0) {
    const detail = errors.map((e) => `${e.property}: ${Object.values(e.constraints ?? {}).join(', ')}`).join('; ');
    throw new Error(`Invalid environment: ${detail}`);
  }
  const strict = env.NODE_ENV === NodeEnv.production || env.NODE_ENV === NodeEnv.staging;
  if (strict) {
    const required = [
      'FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY',
      'R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET_NAME', 'R2_PUBLIC_URL',
    ] as const;
    const missing = required.filter((k) => !env[k]);
    if (missing.length) throw new Error(`Invalid environment: missing ${missing.join(', ')} for ${env.NODE_ENV}`);
    if (env.FIREBASE_AUTH_EMULATOR_HOST) {
      throw new Error('Invalid environment: FIREBASE_AUTH_EMULATOR_HOST must not be set in staging/production');
    }
  }
  return env;
}
