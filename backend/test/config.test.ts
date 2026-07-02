import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.CORS_ORIGIN = 'https://app.example.com';

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
});
