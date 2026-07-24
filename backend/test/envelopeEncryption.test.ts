import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.USER_KEY_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
process.env.DATA_HMAC_KEY = 'test-data-hmac-key-with-at-least-32-characters';

const {
  LocalKeyWrappingProvider,
  blindIndex,
  createUserDataKey,
  decryptUserPayload,
  encryptUserPayload,
} = await import('../src/envelopeEncryption.js');

describe('per-user envelope encryption', () => {
  it('wraps a user key and authenticates encrypted record context', async () => {
    const provider = new LocalKeyWrappingProvider();
    const key = await createUserDataKey(provider);
    const restoredKey = await provider.unwrap(key.wrapped);
    assert.deepEqual(restoredKey, key.plaintext);

    const context = {
      userId: '11111111-1111-4111-8111-111111111111',
      entityType: 'payroll.statement',
      recordId: '22222222-2222-4222-8222-222222222222',
      keyVersion: 1,
      schemaVersion: 1,
    };
    const encrypted = encryptUserPayload(key.plaintext, context, {
      grossPayPaise: 10_941_200,
    });
    assert.deepEqual(
      decryptUserPayload(key.plaintext, context, encrypted),
      { grossPayPaise: 10_941_200 },
    );
    assert.throws(
      () => decryptUserPayload(key.plaintext, {
        ...context,
        userId: '33333333-3333-4333-8333-333333333333',
      }, encrypted),
      /authenticate data/,
    );
  });

  it('creates deterministic namespace-separated blind indexes', () => {
    const email = blindIndex('email', 'user@example.com');
    assert.deepEqual(email, blindIndex('email', 'user@example.com'));
    assert.notDeepEqual(email, blindIndex('phone', 'user@example.com'));
  });
});
