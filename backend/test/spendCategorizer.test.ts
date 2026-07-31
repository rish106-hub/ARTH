import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
// Empty rather than deleted: config.ts pulls in dotenv, which would otherwise
// repopulate a real key from backend/.env and send these tests to the network.
process.env.OPENAI_API_KEY = '';

const { SPEND_CATEGORIES, categorizeTransactions } =
  await import('../src/spendCategorizer.js');
const { setDbForTests, resetDbForTests } = await import('../src/db.js');

function trackingDb() {
  const queries: string[] = [];
  return {
    queries,
    handle: {
      query: async (sql: string) => {
        queries.push(sql);
        return { rowCount: 0, rows: [] };
      },
      connect: async () => ({
        query: async () => ({ rowCount: 0, rows: [] }),
        release: () => undefined,
      }),
    },
  };
}

describe('spend categorizer', () => {
  it('keeps the category list in sync with the app', () => {
    // These strings are persisted and synced, and the Flutter app validates
    // incoming categories against its own copy in lib/models/spend_map.dart.
    assert.equal(SPEND_CATEGORIES.length, 18);
    for (const required of ['food', 'transfer', 'loan', 'fees', 'other']) {
      assert.ok(SPEND_CATEGORIES.includes(required as never), required);
    }
  });

  it('returns an empty result for an empty batch without touching the ledger', async () => {
    const db = trackingDb();
    setDbForTests(db.handle);
    try {
      const results = await categorizeTransactions([]);
      assert.deepEqual(results, []);
      assert.equal(db.queries.length, 0);
    } finally {
      resetDbForTests();
    }
  });

  it('spends nothing when no API key is configured', async () => {
    const db = trackingDb();
    setDbForTests(db.handle);
    try {
      const results = await categorizeTransactions(
        [{ id: 'm:swiggy', merchant: 'SWIGGY', text: 'to SWIGGY' }],
        { userId: 'user-1' },
      );
      // null means "keep the on-device categories", and nothing was billed or
      // even looked up.
      assert.equal(results, null);
      assert.equal(db.queries.length, 0);
    } finally {
      resetDbForTests();
    }
  });
});
