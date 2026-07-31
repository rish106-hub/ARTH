import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.DATA_HMAC_KEY = 'test-data-hmac-key-32-characters-minimum';

const {
  merchantHash,
  normalizeMerchant,
  readMerchantCategories,
  writeMerchantCategories,
} = await import('../src/merchantCategoryCache.js');

type Recorded = { sql: string; params: unknown[] };

function fakeHandle(rows: Record<string, unknown>[], recorded: Recorded[] = []) {
  return {
    query: async (sql: string, params: unknown[] = []) => {
      recorded.push({ sql, params });
      return { rowCount: rows.length, rows };
    },
  };
}

describe('merchant cache keys', () => {
  it('normalises case, spacing and punctuation to one key', () => {
    assert.equal(normalizeMerchant('SWIGGY'), 'swiggy');
    assert.equal(normalizeMerchant('Swiggy '), 'swiggy');
    assert.equal(normalizeMerchant('Swiggy.'), 'swiggy');
    assert.equal(normalizeMerchant('S W I G G Y'), 'swiggy');
  });

  it('refuses a merchant too short to identify a payee', () => {
    assert.equal(normalizeMerchant('AB'), null);
    assert.equal(merchantHash('AB'), null);
    assert.equal(merchantHash(null), null);
  });

  it('hashes every spelling of one merchant to the same digest', () => {
    const canonical = merchantHash('SWIGGY');
    assert.ok(canonical);
    assert.equal(merchantHash('swiggy '), canonical);
    assert.equal(merchantHash('Swiggy.'), canonical);
    assert.notEqual(merchantHash('ZOMATO'), canonical);
  });

  it('stores no readable merchant text', () => {
    const hash = merchantHash('RAHUL SHARMA');
    assert.ok(hash);
    // The cache is shared across users and a payee can be a person, so the key
    // must not contain the name in any recoverable form.
    assert.ok(!hash!.toLowerCase().includes('rahul'));
    assert.match(hash!, /^[0-9a-f]{64}$/);
  });
});

describe('merchant cache reads', () => {
  it('maps rows back by hash', async () => {
    const hash = merchantHash('SWIGGY')!;
    const cached = await readMerchantCategories(
      ['SWIGGY'],
      fakeHandle([
        { merchant_hash: hash, category: 'food', confidence: 'high' },
      ]),
    );
    assert.equal(cached.get(hash)?.category, 'food');
    assert.equal(cached.get(hash)?.confidence, 'high');
  });

  it('ignores a row whose category has since been retired', async () => {
    const hash = merchantHash('SWIGGY')!;
    const cached = await readMerchantCategories(
      ['SWIGGY'],
      fakeHandle([
        { merchant_hash: hash, category: 'crypto-nonsense', confidence: 'high' },
      ]),
    );
    assert.equal(cached.size, 0);
  });

  it('skips the query entirely when nothing is keyable', async () => {
    const recorded: Recorded[] = [];
    const cached = await readMerchantCategories(
      [null, 'AB', undefined],
      fakeHandle([], recorded),
    );
    assert.equal(cached.size, 0);
    assert.equal(recorded.length, 0);
  });

  it('treats a cache failure as a cache miss rather than throwing', async () => {
    const cached = await readMerchantCategories(['SWIGGY'], {
      query: async () => {
        throw new Error('relation "merchant_category_cache" does not exist');
      },
    });
    assert.equal(cached.size, 0);
  });
});

describe('merchant cache writes', () => {
  it('shares confident answers only', async () => {
    const recorded: Recorded[] = [];
    await writeMerchantCategories(
      [
        { merchant: 'SWIGGY', category: 'food', confidence: 'high', model: 'm' },
        { merchant: 'ZOMATO', category: 'food', confidence: 'medium', model: 'm' },
        { merchant: 'APOLLO', category: 'health', confidence: 'low', model: 'm' },
      ],
      fakeHandle([], recorded),
    );
    // A guess the model was unsure about must never become another user's
    // silent answer.
    assert.equal(recorded.length, 1);
    assert.equal(recorded[0].params[0], merchantHash('SWIGGY'));
    assert.equal(recorded[0].params[1], 'food');
  });

  it('writes nothing when no merchant is keyable', async () => {
    const recorded: Recorded[] = [];
    await writeMerchantCategories(
      [{ merchant: 'AB', category: 'food', confidence: 'high', model: 'm' }],
      fakeHandle([], recorded),
    );
    assert.equal(recorded.length, 0);
  });
});
