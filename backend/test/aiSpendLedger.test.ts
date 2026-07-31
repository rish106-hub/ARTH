import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.AI_SPEND_CAP_USD = '1.5';
process.env.AI_ITEMS_PER_USER_PER_DAY = '200';

const {
  capMicroUsd,
  costMicroUsd,
  evaluateBudget,
  priceForModel,
  readSpend,
  recordSpend,
  tryReadSpend,
  worstCaseMicroUsd,
} = await import('../src/aiSpendLedger.js');

type Recorded = { sql: string; params: unknown[] };

function fakeHandle(rows: Record<string, unknown>[], recorded: Recorded[] = []) {
  return {
    query: async (sql: string, params: unknown[] = []) => {
      recorded.push({ sql, params });
      return { rowCount: rows.length, rows };
    },
  };
}

function throwingHandle() {
  return {
    query: async () => {
      throw Object.assign(new Error('relation "ai_spend_ledger" does not exist'), {
        code: '42P01',
      });
    },
  };
}

describe('ai spend pricing', () => {
  it('bills cached input cheaper than fresh input', () => {
    const fresh = costMicroUsd('gpt-5.4-nano', {
      inputTokens: 1_000_000,
      cachedInputTokens: 0,
      outputTokens: 0,
    });
    const cached = costMicroUsd('gpt-5.4-nano', {
      inputTokens: 1_000_000,
      cachedInputTokens: 1_000_000,
      outputTokens: 0,
    });
    assert.equal(fresh, 200_000); // $0.20
    assert.equal(cached, 20_000); // $0.02, a tenth
  });

  it('splits partly-cached input across both rates', () => {
    // 600k cached at $0.02/M + 400k fresh at $0.20/M = 12_000 + 80_000
    const cost = costMicroUsd('gpt-5.4-nano', {
      inputTokens: 1_000_000,
      cachedInputTokens: 600_000,
      outputTokens: 0,
    });
    assert.equal(cost, 92_000);
  });

  it('rounds up, so many tiny calls cannot under-count against the cap', () => {
    const cost = costMicroUsd('gpt-5.4-nano', {
      inputTokens: 1,
      cachedInputTokens: 0,
      outputTokens: 0,
    });
    // 0.2 µUSD rounds to 1, never to 0.
    assert.equal(cost, 1);
  });

  it('prices an unknown model at the most expensive known rate', () => {
    const unknown = priceForModel('gpt-6-experimental');
    const pro = priceForModel('gpt-5.5-pro');
    assert.deepEqual(unknown, pro);
    // Critically, NOT the cheap default: an unpriced model must throttle rather
    // than quietly overspend.
    assert.ok(unknown.outputPerMillion > priceForModel('gpt-5.4-nano').outputPerMillion);
  });

  it('charges the worst case as fully uncached input plus the whole output allowance', () => {
    const worst = worstCaseMicroUsd('gpt-5.4-nano', 1_000_000, 1_000_000);
    assert.equal(worst, 200_000 + 1_250_000);
  });
});

describe('ai spend budget', () => {
  const snapshot = (spent: number, userItems = 0) => ({
    spentMicroUsd: spent,
    remainingMicroUsd: Math.max(0, capMicroUsd() - spent),
    userItemsToday: userItems,
  });

  it('allows a call that fits inside the cap', () => {
    const verdict = evaluateBudget(snapshot(0), 1_000, 10);
    assert.equal(verdict.allowed, true);
  });

  it('denies with cap_reached when the worst case does not fit', () => {
    // $1.4999 spent of $1.50 leaves 100 µUSD.
    const verdict = evaluateBudget(snapshot(capMicroUsd() - 100), 1_000, 1);
    assert.equal(verdict.allowed, false);
    assert.equal(verdict.allowed === false && verdict.reason, 'cap_reached');
  });

  it('blocks entirely rather than allowing a partial run near the cap', () => {
    const nearlyGone = snapshot(capMicroUsd() - 1);
    assert.equal(evaluateBudget(nearlyGone, 2, 1).allowed, false);
  });

  it('denies with user_quota when the daily item allowance is exceeded', () => {
    const verdict = evaluateBudget(snapshot(0, 195), 1_000, 10);
    assert.equal(verdict.allowed, false);
    assert.equal(verdict.allowed === false && verdict.reason, 'user_quota');
  });

  it('counts the items in this call against the quota, not just past ones', () => {
    assert.equal(evaluateBudget(snapshot(0, 199), 1_000, 1).allowed, true);
    assert.equal(evaluateBudget(snapshot(0, 199), 1_000, 2).allowed, false);
  });
});

describe('ai spend ledger persistence', () => {
  it('derives remaining budget from the global total, not one user', async () => {
    const snapshot = await readSpend(
      'user-1',
      fakeHandle([{ spent: '500000', user_items: '12' }]),
    );
    assert.equal(snapshot.spentMicroUsd, 500_000);
    assert.equal(snapshot.remainingMicroUsd, capMicroUsd() - 500_000);
    assert.equal(snapshot.userItemsToday, 12);
  });

  it('records the priced cost alongside the reported token counts', async () => {
    const recorded: Recorded[] = [];
    await recordSpend(
      {
        userId: 'user-1',
        model: 'gpt-5.4-nano',
        usage: { inputTokens: 1_000_000, cachedInputTokens: 0, outputTokens: 0 },
        items: 7,
      },
      fakeHandle([], recorded),
    );
    assert.equal(recorded.length, 1);
    const [userId, model, input, cached, output, micro, items] = recorded[0].params;
    assert.equal(userId, 'user-1');
    assert.equal(model, 'gpt-5.4-nano');
    assert.equal(input, 1_000_000);
    assert.equal(cached, 0);
    assert.equal(output, 0);
    assert.equal(micro, 200_000);
    assert.equal(items, 7);
  });

  it('fails closed when the ledger cannot be read', async () => {
    // Migrations not run yet, or a database blip. With no way to verify what has
    // been spent there is no way to prove the next call stays inside the cap, so
    // the caller must refuse rather than assume zero.
    const snapshot = await tryReadSpend('user-1', throwingHandle());
    assert.equal(snapshot, null);
  });
});
