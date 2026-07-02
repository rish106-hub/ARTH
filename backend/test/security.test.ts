import assert from 'node:assert/strict';
import { describe, it, before, beforeEach, after } from 'node:test';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.ACCESS_TOKEN_TTL_MINUTES = '15';
process.env.REFRESH_TOKEN_TTL_DAYS = '30';
process.env.CORS_ORIGIN = 'https://app.example.com';

type Row = Record<string, unknown>;
type QueryResult = { rowCount: number; rows: Row[] };

type UserRow = {
  id: string;
  email: string;
  name: string;
  password_hash: string;
  created_at: Date;
  updated_at: Date;
  last_seen_at: Date;
};

type SessionRow = {
  id: string;
  user_id: string;
  token_hash: string;
  expires_at: Date;
  revoked_at: Date | null;
  created_at: Date;
};

class FakeDbClient {
  constructor(private readonly db: FakeDb) {}

  async query(sql: string, params: unknown[] = []) {
    return this.db.query(sql, params);
  }

  release() {}
}

class FakeDb {
  private users = new Map<string, UserRow>();
  private sessions = new Map<string, SessionRow>();
  private profiles = new Map<string, Row>();
  private taxResults = new Map<string, Row>();
  private doneGaps = new Map<string, Set<string>>();
  private events: Row[] = [];
  private ids = 0;

  reset() {
    this.users.clear();
    this.sessions.clear();
    this.profiles.clear();
    this.taxResults.clear();
    this.doneGaps.clear();
    this.events = [];
    this.ids = 0;
  }

  async connect() {
    return new FakeDbClient(this);
  }

  async query(sql: string, params: unknown[] = []): Promise<QueryResult> {
    const normalized = sql.replace(/\s+/g, ' ').trim().toLowerCase();
    if (normalized === 'begin' || normalized === 'commit' || normalized === 'rollback') {
      return rows();
    }

    if (normalized.startsWith('select id from app_users where email = $1')) {
      const user = this.userByEmail(params[0] as string);
      return rows(user ? [{ id: user.id }] : []);
    }

    if (normalized.startsWith('insert into app_users')) {
      const now = new Date();
      const user: UserRow = {
        id: this.nextId('user'),
        email: params[0] as string,
        name: params[1] as string,
        password_hash: params[2] as string,
        created_at: now,
        updated_at: now,
        last_seen_at: now,
      };
      this.users.set(user.id, user);
      return rows([user as unknown as Row]);
    }

    if (normalized.startsWith('select id, email, name, password_hash, created_at from app_users where email = $1')) {
      const user = this.userByEmail(params[0] as string);
      return rows(user ? [user as unknown as Row] : []);
    }

    if (normalized.startsWith('update app_users set last_seen_at = now()')) {
      const user = this.users.get(params[0] as string);
      if (user) {
        user.last_seen_at = new Date();
        user.updated_at = new Date();
      }
      return rows();
    }

    if (normalized.startsWith('insert into auth_refresh_sessions')) {
      const session: SessionRow = {
        id: this.nextId('session'),
        user_id: params[0] as string,
        token_hash: params[1] as string,
        expires_at: params[2] as Date,
        revoked_at: null,
        created_at: new Date(),
      };
      this.sessions.set(session.id, session);
      return rows();
    }

    if (normalized.startsWith('select s.id, s.user_id, s.expires_at, u.email, u.name, u.created_at')) {
      const tokenHash = params[0] as string;
      const session = [...this.sessions.values()].find((candidate) =>
        candidate.token_hash === tokenHash
        && candidate.revoked_at === null
        && candidate.expires_at.getTime() > Date.now(),
      );
      if (!session) return rows();
      const user = this.users.get(session.user_id);
      if (!user) return rows();
      return rows([{
        id: session.id,
        user_id: session.user_id,
        expires_at: session.expires_at,
        email: user.email,
        name: user.name,
        created_at: user.created_at,
      }]);
    }

    if (normalized.startsWith('update auth_refresh_sessions set revoked_at = now() where id = $1')) {
      const session = this.sessions.get(params[0] as string);
      if (session) session.revoked_at = new Date();
      return rows();
    }

    if (normalized.startsWith('update auth_refresh_sessions set revoked_at = now() where token_hash = $1')) {
      const tokenHash = params[0] as string;
      for (const session of this.sessions.values()) {
        if (session.token_hash === tokenHash && session.revoked_at === null) {
          session.revoked_at = new Date();
        }
      }
      return rows();
    }

    if (normalized.startsWith('select id, email, name, created_at from app_users where id = $1')) {
      const user = this.users.get(params[0] as string);
      return rows(user ? [user as unknown as Row] : []);
    }

    if (normalized.startsWith('select * from tax_profiles where user_id = $1 and fy = $2')) {
      const profile = this.profiles.get(key(params[0], params[1]));
      return rows(profile ? [profile] : []);
    }

    if (normalized.startsWith('insert into tax_profiles')) {
      const stored = profileRowFromParams(params);
      this.profiles.set(key(params[0], params[1]), stored);
      return rows();
    }

    if (normalized.startsWith('select payload from tax_results where user_id = $1 and fy = $2')) {
      const result = this.taxResults.get(key(params[0], params[1]));
      return rows(result ? [result] : []);
    }

    if (normalized.startsWith('insert into tax_results')) {
      this.taxResults.set(key(params[0], params[1]), {
        payload: JSON.parse(params[2] as string) as Row,
      });
      return rows();
    }

    if (normalized.startsWith('select gap_id from done_gaps where user_id = $1 and fy = $2')) {
      const ids = [...(this.doneGaps.get(key(params[0], params[1])) ?? new Set())].sort();
      return rows(ids.map((gap_id) => ({ gap_id })));
    }

    if (normalized.startsWith('delete from done_gaps where user_id = $1 and fy = $2')) {
      this.doneGaps.delete(key(params[0], params[1]));
      return rows();
    }

    if (normalized.startsWith('insert into done_gaps')) {
      const doneKey = key(params[0], params[1]);
      const ids = this.doneGaps.get(doneKey) ?? new Set<string>();
      ids.add(params[2] as string);
      this.doneGaps.set(doneKey, ids);
      return rows();
    }

    if (normalized.startsWith('delete from done_gaps where user_id = $1')) {
      this.deleteByUser(this.doneGaps, params[0] as string);
      return rows();
    }

    if (normalized.startsWith('delete from tax_profiles where user_id = $1')) {
      this.deleteByUser(this.profiles, params[0] as string);
      return rows();
    }

    if (normalized.startsWith('delete from tax_results where user_id = $1')) {
      this.deleteByUser(this.taxResults, params[0] as string);
      return rows();
    }

    if (normalized.startsWith('insert into user_events')) {
      this.events.push({
        user_id: params[0],
        name: params[1],
        metadata: JSON.parse(params[2] as string),
      });
      return rows();
    }

    throw new Error(`Unhandled SQL in fake DB: ${normalized}`);
  }

  private userByEmail(email: string) {
    return [...this.users.values()].find((user) => user.email === email);
  }

  private nextId(prefix: string) {
    this.ids += 1;
    return `${prefix}-${this.ids}`;
  }

  private deleteByUser<T>(map: Map<string, T>, userId: string) {
    for (const itemKey of map.keys()) {
      if (itemKey.startsWith(`${userId}:`)) map.delete(itemKey);
    }
  }
}

let buildApp: typeof import('../src/app.js').buildApp;
let setDbForTests: typeof import('../src/db.js').setDbForTests;
let resetDbForTests: typeof import('../src/db.js').resetDbForTests;

const fakeDb = new FakeDb();

before(async () => {
  ({ buildApp } = await import('../src/app.js'));
  ({ setDbForTests, resetDbForTests } = await import('../src/db.js'));
  setDbForTests(fakeDb);
});

beforeEach(() => {
  fakeDb.reset();
});

after(() => {
  resetDbForTests?.();
});

describe('backend security harness', () => {
  it('sets security headers and allows configured CORS origin', async () => {
    const app = await buildApp();
    const response = await app.inject({
      method: 'GET',
      url: '/v1/health',
      headers: { origin: 'https://app.example.com' },
    });

    assert.equal(response.statusCode, 200);
    assert.equal(response.headers['access-control-allow-origin'], 'https://app.example.com');
    assert.equal(response.headers['x-content-type-options'], 'nosniff');
    await app.close();
  });

  it('rejects weak sign-up passwords and sanitizes validation errors', async () => {
    const app = await buildApp();
    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-up',
      payload: {
        name: 'Weak User',
        email: 'weak@example.com',
        password: 'password',
      },
    });

    assert.equal(response.statusCode, 400);
    assert.deepEqual(response.json(), { message: 'Invalid request' });
    await app.close();
  });

  it('signs up, signs in, refreshes, rejects reused refresh token, and signs out', async () => {
    const app = await buildApp();

    const signUp = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-up',
      payload: strongAuthPayload('Auth User', 'auth@example.com'),
    });
    assert.equal(signUp.statusCode, 200);
    const firstRefresh = signUp.json().refreshToken as string;

    const signIn = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-in',
      payload: {
        email: 'auth@example.com',
        password: 'CorrectHorse9',
      },
    });
    assert.equal(signIn.statusCode, 200);

    const refresh = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: firstRefresh },
    });
    assert.equal(refresh.statusCode, 200);

    const reused = await app.inject({
      method: 'POST',
      url: '/v1/auth/refresh',
      payload: { refreshToken: firstRefresh },
    });
    assert.equal(reused.statusCode, 401);

    const signOut = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-out',
      payload: { refreshToken: refresh.json().refreshToken },
    });
    assert.equal(signOut.statusCode, 204);

    await app.close();
  });

  it('rejects missing and invalid bearer tokens', async () => {
    const app = await buildApp();

    const missing = await app.inject({ method: 'GET', url: '/v1/me' });
    assert.equal(missing.statusCode, 401);
    assert.deepEqual(missing.json(), { message: 'Missing bearer token' });

    const invalid = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: 'Bearer not-a-jwt' },
    });
    assert.equal(invalid.statusCode, 401);
    assert.deepEqual(invalid.json(), { message: 'Invalid or expired access token' });

    await app.close();
  });

  it('isolates profile, tax result, and done-gap data by authenticated user', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');

    const aliceProfile = profilePayload('Alice', 'alice@example.com', 1_800_000);
    const putProfile = await app.inject({
      method: 'PUT',
      url: '/v1/profile',
      headers: bearer(alice.accessToken),
      payload: aliceProfile,
    });
    assert.equal(putProfile.statusCode, 200);

    const putResult = await app.inject({
      method: 'PUT',
      url: '/v1/tax-results/current',
      headers: bearer(alice.accessToken),
      payload: { betterRegime: 'newRegime', totalGapAmount: 340000 },
    });
    assert.equal(putResult.statusCode, 200);

    const putGaps = await app.inject({
      method: 'PUT',
      url: '/v1/done-gaps/current',
      headers: bearer(alice.accessToken),
      payload: { gapIds: ['T01_80C_gap'] },
    });
    assert.equal(putGaps.statusCode, 200);

    const bobProfile = await app.inject({
      method: 'GET',
      url: '/v1/profile',
      headers: bearer(bob.accessToken),
    });
    assert.equal(bobProfile.statusCode, 200);
    assert.deepEqual(bobProfile.json(), { profile: null });

    const bobResult = await app.inject({
      method: 'GET',
      url: '/v1/tax-results/current',
      headers: bearer(bob.accessToken),
    });
    assert.deepEqual(bobResult.json(), { taxResult: null });

    const bobGaps = await app.inject({
      method: 'GET',
      url: '/v1/done-gaps/current',
      headers: bearer(bob.accessToken),
    });
    assert.deepEqual(bobGaps.json(), { gapIds: [] });

    await app.close();
  });

  it('keeps plugin errors sanitized while preserving 413 and 429 status codes', async () => {
    const app = await buildApp();

    const tooLarge = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-up',
      payload: { blob: 'x'.repeat(110 * 1024) },
    });
    assert.equal(tooLarge.statusCode, 413);
    assert.deepEqual(tooLarge.json(), { message: 'Request body too large' });

    let limitedStatus = 0;
    for (let i = 0; i < 25; i += 1) {
      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/sign-in',
        payload: { email: `nobody-${i}@example.com`, password: 'WrongPass9' },
      });
      limitedStatus = response.statusCode;
      if (limitedStatus === 429) {
        assert.deepEqual(response.json(), { message: 'Too many requests' });
        break;
      }
    }
    assert.equal(limitedStatus, 429);

    await app.close();
  });
});

function rows(input: Row[] = []): QueryResult {
  return { rowCount: input.length, rows: input };
}

function key(userId: unknown, fy: unknown) {
  return `${String(userId)}:${String(fy)}`;
}

function strongAuthPayload(name: string, email: string) {
  return {
    name,
    email,
    password: 'CorrectHorse9',
  };
}

async function createSession(app: Awaited<ReturnType<typeof buildApp>>, name: string, email: string) {
  const response = await app.inject({
    method: 'POST',
    url: '/v1/auth/sign-up',
    payload: strongAuthPayload(name, email),
  });
  assert.equal(response.statusCode, 200);
  return response.json() as { accessToken: string; refreshToken: string };
}

function bearer(accessToken: string) {
  return { authorization: `Bearer ${accessToken}` };
}

function profilePayload(name: string, email: string, annualCTC: number) {
  return {
    name,
    email,
    annualCTC,
    employmentType: 'salaried',
    city: 'Delhi',
    isMetroCity: true,
    paysRent: true,
    monthlyRent: 35000,
    hasHRA: true,
    invested80C: 70000,
    hasHomeLoan: true,
    propertyType: 'selfOccupied',
    homeLoanInterest: 200000,
    hasNPS: true,
    npsExtraContribution: 50000,
    hasHealthInsuranceSelf: true,
    hasHealthInsuranceParents: true,
    parentsAbove60: true,
    hasEducationLoan: true,
    educationLoanRepaymentYear: 3,
    educationLoanInterest: 60000,
    hasDonations: true,
    donationAmount: 25000,
    ageGroup: 'age30to45',
  };
}

function profileRowFromParams(params: unknown[]): Row {
  return {
    user_id: params[0],
    fy: params[1],
    name: params[2],
    email: params[3],
    annual_ctc: params[4],
    employment_type: params[5],
    city: params[6],
    is_metro_city: params[7],
    pays_rent: params[8],
    monthly_rent: params[9],
    has_hra: params[10],
    invested_80c: params[11],
    has_home_loan: params[12],
    property_type: params[13],
    home_loan_interest: params[14],
    has_nps: params[15],
    nps_extra_contribution: params[16],
    has_health_insurance_self: params[17],
    has_health_insurance_parents: params[18],
    parents_above_60: params[19],
    has_education_loan: params[20],
    education_loan_repayment_year: params[21],
    education_loan_interest: params[22],
    has_donations: params[23],
    donation_amount: params[24],
    age_group: params[25],
  };
}
