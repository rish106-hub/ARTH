import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { after, before, beforeEach, describe, it } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET =
  'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET =
  'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.PAN_HASH_KEY = 'test-pan-hash-key-32-characters-min';
process.env.DATA_HMAC_KEY = 'test-data-hmac-key-32-characters-minimum';
process.env.DOCUMENT_ENCRYPTION_KEY = Buffer.from(
  'abcdef0123456789abcdef0123456789',
).toString('base64');

const { privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
process.env.FIREBASE_SERVICE_ACCOUNT_JSON = Buffer.from(JSON.stringify({
  client_email: 'push-test@arth-test.iam.gserviceaccount.com',
  private_key: privateKey.export({ format: 'pem', type: 'pkcs8' }).toString(),
  project_id: 'arth-test',
})).toString('base64');

type TokenRow = {
  id: string;
  user_id: string;
  token_ciphertext: string;
  token_iv: string;
  token_auth_tag: string;
};

type SalaryUser = {
  user_id: string;
  salary_credit_day: number;
};

class PushFakeDb {
  tokens = new Map<string, TokenRow>();
  claims = new Map<string, { id: string; userId: string }>();
  prunes = 0;
  salaryUsers: SalaryUser[] = [];
  private nextId = 0;

  reset() {
    this.tokens.clear();
    this.claims.clear();
    this.prunes = 0;
    this.salaryUsers = [];
    this.nextId = 0;
  }

  async query(sql: string, params: unknown[] = []) {
    const normalized = sql.replace(/\s+/g, ' ').trim().toLowerCase();
    if (normalized === 'begin'
      || normalized === 'commit'
      || normalized === 'rollback'
      || normalized === 'set transaction isolation level read committed') {
      return { rowCount: 0, rows: [] };
    }
    if (normalized.startsWith("select set_config('application_name'")
      || normalized.startsWith("select set_config('arth.system'")) {
      return { rowCount: 0, rows: [] };
    }
    if (normalized.startsWith('select id, token_ciphertext')) {
      return {
        rowCount: this.tokens.size,
        rows: [...this.tokens.values()].filter(
          (row) => row.user_id === params[0],
        ),
      };
    }
    if (normalized.startsWith('select user_id from spend_maps')) {
      const lastDay = Number(params[0]);
      const day = Number(params[1]);
      const rows = this.salaryUsers.filter(
        (row) => Math.min(row.salary_credit_day, lastDay) <= day,
      );
      return {
        rowCount: rows.length,
        rows: rows.map((row) => ({ user_id: row.user_id })),
      };
    }
    if (normalized.startsWith('delete from push_delivery_claims where created_at')) {
      this.prunes += 1;
      return { rowCount: 0, rows: [] };
    }
    if (normalized.startsWith('insert into push_delivery_claims')) {
      const key = `${params[0]}:${params[1]}:${params[2] ?? 'current_date'}`;
      if (this.claims.has(key)) return { rowCount: 0, rows: [] };
      const id = `claim-${++this.nextId}`;
      this.claims.set(key, { id, userId: String(params[0]) });
      return { rowCount: 1, rows: [{ id }] };
    }
    if (normalized.startsWith('delete from device_tokens where id = any')) {
      for (const id of params[0] as string[]) this.tokens.delete(id);
      return { rowCount: 1, rows: [] };
    }
    if (normalized.startsWith('delete from push_delivery_claims where id')) {
      const entry = [...this.claims.entries()]
        .find(([, claim]) => claim.id === params[0]);
      if (entry) this.claims.delete(entry[0]);
      return { rowCount: entry ? 1 : 0, rows: [] };
    }
    throw new Error(`Unhandled SQL in push fake DB: ${normalized}`);
  }

  async connect() {
    return {
      query: (sql: string, params?: unknown[]) => this.query(sql, params),
      release: () => {},
    };
  }
}

const fakeDb = new PushFakeDb();
let sendPushToUser: typeof import('../src/pushNotifications.js').sendPushToUser;
let sendPaydayCloseReminders:
  typeof import('../src/pushNotifications.js').sendPaydayCloseReminders;
let resetPushState:
  typeof import('../src/pushNotifications.js').resetPushNotificationStateForTests;
let encryptDocument: typeof import('../src/security.js').encryptDocument;
let setDbForTests: typeof import('../src/db.js').setDbForTests;
let resetDbForTests: typeof import('../src/db.js').resetDbForTests;
let fcmResponse: () => Response;
let fcmCalls = 0;

function addToken(id: string, userId: string) {
  const encrypted = encryptDocument(Buffer.from(`token-${id}`));
  fakeDb.tokens.set(id, {
    id,
    user_id: userId,
    token_ciphertext: encrypted.ciphertext,
    token_iv: encrypted.iv,
    token_auth_tag: encrypted.authTag,
  });
}

before(async () => {
  const pushModule = await import('../src/pushNotifications.js');
  const securityModule = await import('../src/security.js');
  const dbModule = await import('../src/db.js');
  sendPushToUser = pushModule.sendPushToUser;
  sendPaydayCloseReminders = pushModule.sendPaydayCloseReminders;
  resetPushState = pushModule.resetPushNotificationStateForTests;
  encryptDocument = securityModule.encryptDocument;
  setDbForTests = dbModule.setDbForTests;
  resetDbForTests = dbModule.resetDbForTests;
  setDbForTests(fakeDb as never);
});

beforeEach(() => {
  fakeDb.reset();
  resetPushState();
  fcmCalls = 0;
  fcmResponse = () => Response.json({ name: 'messages/test' });
  globalThis.fetch = async (input) => {
    if (new URL(String(input)).hostname === 'oauth2.googleapis.com') {
      return Response.json({ access_token: 'test-access-token', expires_in: 3600 });
    }
    fcmCalls += 1;
    return fcmResponse();
  };
});

after(() => {
  resetDbForTests();
});

describe('push notification delivery', () => {
  it('delivers once per daily key and prunes old claims', async () => {
    addToken('token-1', 'user-1');

    const payload = {
      title: 'Overspend',
      body: 'Review spending',
      dailyDedupeKey: 'spend_overspend',
    };
    await sendPushToUser('user-1', payload);
    await sendPushToUser('user-1', payload);

    assert.equal(fcmCalls, 1);
    assert.equal(fakeDb.claims.size, 1);
    assert.equal(fakeDb.prunes, 1);
  });

  it('prunes an unregistered token and releases its delivery claim', async () => {
    addToken('token-1', 'user-1');
    fcmResponse = () => Response.json({
      error: {
        status: 'NOT_FOUND',
        details: [{ errorCode: 'UNREGISTERED' }],
      },
    }, { status: 404 });

    await sendPushToUser('user-1', {
      title: 'Overspend',
      body: 'Review spending',
      dailyDedupeKey: 'spend_overspend',
    });

    assert.equal(fakeDb.tokens.size, 0);
    assert.equal(fakeDb.claims.size, 0);
  });

  it('keeps the token but releases the claim after a provider error', async () => {
    addToken('token-1', 'user-1');
    fcmResponse = () => Response.json({
      error: { status: 'INTERNAL' },
    }, { status: 500 });

    await sendPushToUser('user-1', {
      title: 'Overspend',
      body: 'Review spending',
      dailyDedupeKey: 'spend_overspend',
    });

    assert.equal(fakeDb.tokens.size, 1);
    assert.equal(fakeDb.claims.size, 0);
  });

  it('sends a deduplicated monthly-close push to payday users', async () => {
    addToken('token-1', 'user-1');
    fakeDb.salaryUsers = [{ user_id: 'user-1', salary_credit_day: 28 }];

    await sendPaydayCloseReminders(new Date('2026-07-28T04:00:00.000Z'));
    await sendPaydayCloseReminders(new Date('2026-07-28T05:00:00.000Z'));

    assert.equal(fcmCalls, 1);
    assert.equal(fakeDb.claims.size, 1);
  });

  it('does not send monthly-close reminders before the salary day', async () => {
    addToken('token-1', 'user-1');
    fakeDb.salaryUsers = [{ user_id: 'user-1', salary_credit_day: 28 }];

    await sendPaydayCloseReminders(new Date('2026-07-27T04:00:00.000Z'));

    assert.equal(fcmCalls, 0);
    assert.equal(fakeDb.claims.size, 0);
  });

  it('catches up monthly-close reminders after a missed payday day', async () => {
    addToken('token-1', 'user-1');
    fakeDb.salaryUsers = [{ user_id: 'user-1', salary_credit_day: 28 }];

    await sendPaydayCloseReminders(new Date('2026-07-29T04:00:00.000Z'));

    assert.equal(fcmCalls, 1);
    assert.equal(fakeDb.claims.size, 1);
  });

  it('uses one month bucket even when the salary day changes mid-month', async () => {
    addToken('token-1', 'user-1');
    fakeDb.salaryUsers = [{ user_id: 'user-1', salary_credit_day: 28 }];

    await sendPaydayCloseReminders(new Date('2026-07-28T04:00:00.000Z'));
    fakeDb.salaryUsers = [{ user_id: 'user-1', salary_credit_day: 29 }];
    await sendPaydayCloseReminders(new Date('2026-07-29T04:00:00.000Z'));

    assert.equal(fcmCalls, 1);
    assert.equal(fakeDb.claims.size, 1);
  });
});
