import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
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
  GEMINI_API_KEY: z.string().min(20).optional(),
  GEMINI_MODEL: z.string().default('gemini-3.6-flash'),
  GEMINI_TIMEOUT_MS: z.coerce.number().int().min(1_000).max(60_000).default(25_000),
  SARVAM_API_KEY: z.string().min(10).optional(),
  SARVAM_API_BASE_URL: z.string().url().default('https://api.sarvam.ai'),
  SARVAM_DOCUMENT_LANGUAGE: z.string().regex(/^[a-z]{2,3}-[A-Z]{2}$/).default('hi-IN'),
  SARVAM_TIMEOUT_MS: z.coerce.number().int().min(5_000).max(45_000).default(25_000),
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
