import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  DB_DIALECT: z.enum(['postgres', 'cockroach']).default('postgres'),
  PORT: z.coerce.number().default(8787),
  HOST: z.string().default('0.0.0.0'),
  DATABASE_URL: z.string().min(1),
  JWT_ACCESS_SECRET: z.string().min(64),
  JWT_REFRESH_SECRET: z.string().min(64),
  ACCESS_TOKEN_TTL_MINUTES: z.coerce.number().int().min(5).max(60).default(15),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(30).default(30),
  DB_POOL_MAX: z.coerce.number().int().min(1).max(20).default(5),
  DB_IDLE_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(120_000).default(30_000),
  DB_CONNECTION_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(30_000).default(10_000),
  CURRENT_FY: z.string().default('2025-26'),
  CORS_ORIGIN: z.string().default('*'),
  PAN_ENCRYPTION_KEY: z.string().optional(),
  PAN_HASH_KEY: z.string().optional(),
  DOCUMENT_ENCRYPTION_KEY: z.string().optional(),
  USER_KEY_ENCRYPTION_KEY: z.string().optional(),
  DATA_HMAC_KEY: z.string().optional(),
  GCP_KMS_KEY_NAME: z.string().optional(),
  GCS_DOCUMENT_BUCKET: z.string().optional(),
  GCS_LOCATION: z.string().default('asia-south1'),
  GEMINI_API_KEY: z.string().min(20).optional(),
  GEMINI_MODEL: z.string().default('gemini-3.6-flash'),
  GEMINI_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(60_000).default(25_000),
  OPENAI_API_KEY: z.string().min(20).optional(),
  // Classification is an easy task, so the cheapest model in the 5.4 family
  // runs it and only genuine disagreements reach ESCALATION_MODEL. Larger
  // models are priced in aiSpendLedger and can be set here, but note gpt-5.5
  // bills output at 24x gpt-5.4-nano for no gain on a labelling task.
  OPENAI_MODEL: z.string().default('gpt-5.4-nano'),
  OPENAI_ESCALATION_MODEL: z.string().default('gpt-5.4-mini'),
  OPENAI_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(60_000).default(20_000),
  // Hard lifetime ceiling on paid categorization, in USD. Enforced server-side
  // against recorded usage — see aiSpendLedger.
  AI_SPEND_CAP_USD: z.coerce.number().min(0).max(1_000).default(1.5),
  // Per-account daily item allowance, so one inbox cannot drain the shared cap.
  AI_ITEMS_PER_USER_PER_DAY: z.coerce.number().int().min(0).max(10_000).default(200),
  SARVAM_API_KEY: z.string().min(10).optional(),
  SARVAM_API_BASE_URL: z.string().url().default('https://api.sarvam.ai'),
  SARVAM_DOCUMENT_LANGUAGE: z.string().regex(/^[a-z]{2,3}-[A-Z]{2}$/).default('hi-IN'),
  SARVAM_TIMEOUT_MS: z.coerce.number().int().min(5_000).max(540_000).default(480_000),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().min(100).optional(),
  GOOGLE_OAUTH_CLIENT_ID: z.string().endsWith('.apps.googleusercontent.com').optional(),
}).superRefine((env, ctx) => {
  if (env.JWT_ACCESS_SECRET === env.JWT_REFRESH_SECRET) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['JWT_REFRESH_SECRET'],
      message: 'JWT_REFRESH_SECRET must differ from JWT_ACCESS_SECRET',
    });
  }

  if (env.NODE_ENV !== 'production') return;

  if (env.DB_DIALECT === 'cockroach') {
    let databaseUrl: URL | undefined;
    try {
      databaseUrl = new URL(env.DATABASE_URL);
    } catch {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['DATABASE_URL'],
        message: 'DATABASE_URL must be a valid PostgreSQL connection URL',
      });
    }
    if (databaseUrl?.searchParams.get('sslmode') !== 'verify-full') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['DATABASE_URL'],
        message: 'CockroachDB production connections require sslmode=verify-full',
      });
    }
    if (!env.GCP_KMS_KEY_NAME) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['GCP_KMS_KEY_NAME'],
        message: 'GCP_KMS_KEY_NAME is required for CockroachDB production',
      });
    }
    if (!env.GCS_DOCUMENT_BUCKET) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['GCS_DOCUMENT_BUCKET'],
        message: 'GCS_DOCUMENT_BUCKET is required for CockroachDB production',
      });
    }
    if (!env.DATA_HMAC_KEY || env.DATA_HMAC_KEY.length < 32) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['DATA_HMAC_KEY'],
        message: 'DATA_HMAC_KEY is required for CockroachDB production and must be at least 32 characters',
      });
    }
    if (env.GCS_LOCATION !== 'asia-south1') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['GCS_LOCATION'],
        message: 'GCS_LOCATION must be asia-south1',
      });
    }
  }

  if (!env.PAN_ENCRYPTION_KEY) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['PAN_ENCRYPTION_KEY'],
      message: 'PAN_ENCRYPTION_KEY is required in production',
    });
  } else {
    try {
      if (Buffer.from(env.PAN_ENCRYPTION_KEY, 'base64').length !== 32) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['PAN_ENCRYPTION_KEY'],
          message: 'PAN_ENCRYPTION_KEY must be 32 base64-encoded bytes',
        });
      }
    } catch {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['PAN_ENCRYPTION_KEY'],
        message: 'PAN_ENCRYPTION_KEY must be valid base64',
      });
    }
  }

  if (!env.PAN_HASH_KEY || env.PAN_HASH_KEY.length < 32) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['PAN_HASH_KEY'],
      message: 'PAN_HASH_KEY is required in production and must be at least 32 characters',
    });
  }

  if (!env.DOCUMENT_ENCRYPTION_KEY) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['DOCUMENT_ENCRYPTION_KEY'],
      message: 'DOCUMENT_ENCRYPTION_KEY is required in production',
    });
  } else {
    try {
      if (Buffer.from(env.DOCUMENT_ENCRYPTION_KEY, 'base64').length !== 32) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['DOCUMENT_ENCRYPTION_KEY'],
          message: 'DOCUMENT_ENCRYPTION_KEY must be 32 base64-encoded bytes',
        });
      }
    } catch {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['DOCUMENT_ENCRYPTION_KEY'],
        message: 'DOCUMENT_ENCRYPTION_KEY must be valid base64',
      });
    }
  }

  const corsOrigins = env.CORS_ORIGIN.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  if (corsOrigins.length === 0 || corsOrigins.includes('*')) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ['CORS_ORIGIN'],
      message: 'CORS_ORIGIN must be explicit in production',
    });
  }

  for (const origin of corsOrigins) {
    try {
      const parsed = new URL(origin);
      if (parsed.protocol !== 'https:') {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ['CORS_ORIGIN'],
          message: 'Production CORS origins must use HTTPS',
        });
      }
    } catch {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['CORS_ORIGIN'],
        message: 'CORS_ORIGIN contains an invalid URL',
      });
    }
  }

  for (const key of ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET'] as const) {
    const value = env[key].toLowerCase();
    if (
      value.includes('replace-with')
      || value.includes('placeholder')
      || value.includes('change-me')
      || value.includes('secret-manager')
      || value.includes('example')
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: [key],
        message: `${key} must be a real random production secret`,
      });
    }
  }
});

export type Env = z.infer<typeof envSchema>;

export function parseEnv(input: NodeJS.ProcessEnv): Env {
  return envSchema.parse(input);
}

export const env = parseEnv(process.env);
