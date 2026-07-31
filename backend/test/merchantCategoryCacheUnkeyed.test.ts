import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

// This file proves the cache turns itself off without a usable HMAC key, rather
// than falling back to storing merchant names in a recoverable form.
//
// The keys are set EMPTY rather than deleted on purpose: config.ts pulls in
// dotenv, which repopulates anything absent from the developer's real
// backend/.env, so a delete here would silently be undone.
process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.DATA_HMAC_KEY = '';
process.env.PAN_HASH_KEY = '';

const { merchantHash, readMerchantCategories, writeMerchantCategories } =
  await import('../src/merchantCategoryCache.js');

describe('merchant cache without a usable HMAC key', () => {
  it('produces no hash at all', () => {
    assert.equal(merchantHash('SWIGGY'), null);
  });

  it('reads nothing and never queries', async () => {
    let queried = false;
    const cached = await readMerchantCategories(['SWIGGY'], {
      query: async () => {
        queried = true;
        return { rowCount: 0, rows: [] };
      },
    });
    assert.equal(cached.size, 0);
    assert.equal(queried, false);
  });

  it('writes nothing', async () => {
    let queried = false;
    await writeMerchantCategories(
      [{ merchant: 'SWIGGY', category: 'food', confidence: 'high', model: 'm' }],
      {
        query: async () => {
          queried = true;
          return { rowCount: 0, rows: [] };
        },
      },
    );
    assert.equal(queried, false);
  });
});
