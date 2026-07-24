import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.CORS_ORIGIN = 'https://app.example.com';
process.env.PAN_ENCRYPTION_KEY = Buffer.from('0123456789abcdef0123456789abcdef').toString('base64');
process.env.PAN_HASH_KEY = 'test-pan-hash-key-32-characters-min';
process.env.DOCUMENT_ENCRYPTION_KEY = Buffer.from('abcdef0123456789abcdef0123456789').toString('base64');

const { parseEnv } = await import('../src/config.js');

const baseEnv = {
  NODE_ENV: 'production',
  PORT: '8787',
  HOST: '0.0.0.0',
  DATABASE_URL: 'postgres://user:pass@db.example.com:5432/arth?sslmode=require',
  JWT_ACCESS_SECRET: 'prod-access-0000000000000000000000000000000000000000000000000000',
  JWT_REFRESH_SECRET: 'prod-refresh-111111111111111111111111111111111111111111111111111111',
  ACCESS_TOKEN_TTL_MINUTES: '15',
  REFRESH_TOKEN_TTL_DAYS: '30',
  DB_POOL_MAX: '5',
  DB_IDLE_TIMEOUT_MS: '30000',
  DB_CONNECTION_TIMEOUT_MS: '10000',
  CURRENT_FY: '2026-27',
  CORS_ORIGIN: 'https://arth.example.com',
  PAN_ENCRYPTION_KEY: Buffer.from('0123456789abcdef0123456789abcdef').toString('base64'),
  PAN_HASH_KEY: 'prod-pan-hash-key-32-characters-min',
  DOCUMENT_ENCRYPTION_KEY: Buffer.from('abcdef0123456789abcdef0123456789').toString('base64'),
};

describe('env validation', () => {
  it('accepts strict production env', () => {
    const parsed = parseEnv(baseEnv);
    assert.equal(parsed.NODE_ENV, 'production');
    assert.equal(parsed.CORS_ORIGIN, 'https://arth.example.com');
    assert.equal(parsed.DB_POOL_MAX, 5);
  });

  it('rejects wildcard production CORS', () => {
    assert.throws(() => parseEnv({ ...baseEnv, CORS_ORIGIN: '*' }), /CORS_ORIGIN/);
  });

  it('rejects non-HTTPS production CORS origins', () => {
    assert.throws(
      () => parseEnv({ ...baseEnv, CORS_ORIGIN: 'http://arth.example.com' }),
      /Production CORS origins must use HTTPS/,
    );
  });

  it('rejects matching JWT secrets', () => {
    assert.throws(
      () => parseEnv({
        ...baseEnv,
        JWT_REFRESH_SECRET: baseEnv.JWT_ACCESS_SECRET,
      }),
      /JWT_REFRESH_SECRET must differ/,
    );
  });

  it('rejects placeholder production JWT secrets', () => {
    assert.throws(
      () => parseEnv({
        ...baseEnv,
        JWT_ACCESS_SECRET: 'replace-with-at-least-64-random-characters-generated-by-a-secret-manager',
      }),
      /real random production secret/,
    );
  });

  it('rejects missing or weak production PAN keys', () => {
    const { PAN_ENCRYPTION_KEY, ...withoutEncryptionKey } = baseEnv;
    assert.throws(
      () => parseEnv(withoutEncryptionKey),
      /PAN_ENCRYPTION_KEY is required/,
    );
    assert.throws(
      () => parseEnv({
        ...baseEnv,
        PAN_ENCRYPTION_KEY: Buffer.from('short').toString('base64'),
      }),
      /PAN_ENCRYPTION_KEY must be 32 base64-encoded bytes/,
    );
    assert.throws(
      () => parseEnv({
        ...baseEnv,
        PAN_HASH_KEY: 'short',
      }),
      /PAN_HASH_KEY is required/,
    );
  });

  it('rejects missing or weak production document key', () => {
    const { DOCUMENT_ENCRYPTION_KEY, ...withoutDocumentKey } = baseEnv;
    assert.throws(
      () => parseEnv(withoutDocumentKey),
      /DOCUMENT_ENCRYPTION_KEY is required/,
    );
    assert.throws(
      () => parseEnv({
        ...baseEnv,
        DOCUMENT_ENCRYPTION_KEY: Buffer.from('short').toString('base64'),
      }),
      /DOCUMENT_ENCRYPTION_KEY must be 32 base64-encoded bytes/,
    );
  });

  it('requires verified TLS, KMS, GCS, and blind-index keys for CockroachDB', () => {
    const cockroachEnv = {
      ...baseEnv,
      DB_DIALECT: 'cockroach',
      DATABASE_URL: 'postgresql://user:pass@cluster.cockroachlabs.cloud:26257/arth?sslmode=verify-full',
      GCP_KMS_KEY_NAME: 'projects/arth/locations/asia-south1/keyRings/app/cryptoKeys/user-data',
      GCS_DOCUMENT_BUCKET: 'arth-private-documents',
      GCS_LOCATION: 'asia-south1',
      DATA_HMAC_KEY: 'prod-data-hmac-key-with-at-least-32-characters',
    };
    assert.equal(parseEnv(cockroachEnv).DB_DIALECT, 'cockroach');
    assert.throws(
      () => parseEnv({
        ...cockroachEnv,
        DATABASE_URL: 'postgresql://user:pass@cluster.cockroachlabs.cloud:26257/arth?sslmode=require',
      }),
      /sslmode=verify-full/,
    );
    assert.throws(
      () => parseEnv({ ...cockroachEnv, DATA_HMAC_KEY: 'short' }),
      /DATA_HMAC_KEY/,
    );
  });
});
