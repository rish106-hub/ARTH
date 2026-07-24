import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';

const { runSerializableTransaction } = await import('../src/db.js');

describe('Cockroach transaction retry', () => {
  it('retries the complete transaction after SQLSTATE 40001', async () => {
    let attempts = 0;
    let releases = 0;
    const handle = {
      async query() {
        return { rowCount: 0, rows: [] };
      },
      async connect() {
        attempts += 1;
        return {
          async query(sql: string) {
            if (sql === 'begin' || sql === 'commit' || sql === 'rollback') {
              return { rowCount: 0, rows: [] };
            }
            return { rowCount: 1, rows: [{ ok: true }] };
          },
          release() {
            releases += 1;
          },
        };
      },
    };

    const result = await runSerializableTransaction(async (client) => {
      if (attempts === 1) {
        throw Object.assign(new Error('restart transaction'), { code: '40001' });
      }
      return client.query('select 1');
    }, handle);

    assert.equal(attempts, 2);
    assert.equal(releases, 2);
    assert.equal(result.rowCount, 1);
  });
});
