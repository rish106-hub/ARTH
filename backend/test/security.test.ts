import assert from 'node:assert/strict';
import { describe, it, before, beforeEach, after } from 'node:test';
import { parseForm16Text } from '../src/documentParser.js';

process.env.NODE_ENV = 'test';
process.env.DATABASE_URL = 'postgres://test:test@localhost:5432/test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret-64-characters-minimum-000000000000000000000000';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret-64-characters-minimum-00000000000000000000000';
process.env.ACCESS_TOKEN_TTL_MINUTES = '15';
process.env.REFRESH_TOKEN_TTL_DAYS = '30';
process.env.CORS_ORIGIN = 'https://app.example.com';
process.env.PAN_ENCRYPTION_KEY = Buffer.from('0123456789abcdef0123456789abcdef').toString('base64');
process.env.PAN_HASH_KEY = 'test-pan-hash-key-32-characters-min';
process.env.DATA_HMAC_KEY = 'test-data-hmac-key-32-characters-minimum';
process.env.DOCUMENT_ENCRYPTION_KEY = Buffer.from('abcdef0123456789abcdef0123456789').toString('base64');

type Row = Record<string, unknown>;
type QueryResult = { rowCount: number; rows: Row[] };

type UserRow = {
  id: string;
  email: string;
  name: string;
  phone_e164: string | null;
  avatar_initials: string | null;
  avatar_color: string | null;
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
  private identities = new Map<string, Row>();
  private documents = new Map<string, Row>();
  private offerComparisons = new Map<string, Row>();
  private offerComparisonOffers: Row[] = [];
  private moneyGoals = new Map<string, Row>();
  private spendMaps = new Map<string, Row>();
  private userState = new Map<string, Row>();
  private userStateContexts: string[] = [];
  private employers = new Map<string, Row>();
  private deviceTokens = new Map<string, Row>();
  private events: Row[] = [];
  private tombstones: Row[] = [];
  private ids = 0;
  private transientEmailLookupFailures = 0;

  reset() {
    this.users.clear();
    this.sessions.clear();
    this.profiles.clear();
    this.taxResults.clear();
    this.doneGaps.clear();
    this.identities.clear();
    this.documents.clear();
    this.offerComparisons.clear();
    this.offerComparisonOffers = [];
    this.moneyGoals.clear();
    this.spendMaps.clear();
    this.userState.clear();
    this.userStateContexts = [];
    this.employers.clear();
    this.deviceTokens.clear();
    this.events = [];
    this.tombstones = [];
    this.ids = 0;
    this.transientEmailLookupFailures = 0;
  }

  failNextEmailLookups(count: number) {
    this.transientEmailLookupFailures = count;
  }

  rawIdentity(userId: string) {
    return this.identities.get(userId);
  }

  rawDocument(documentId: string) {
    return this.documents.get(documentId);
  }

  rawDeviceTokens() {
    return [...this.deviceTokens.values()];
  }

  rawUserState() {
    return [...this.userState.values()];
  }

  rawSpendMap(userId: string) {
    return this.spendMaps.get(userId);
  }

  rawUserStateContexts() {
    return [...this.userStateContexts];
  }

  hasUser(userId: string) {
    return this.users.has(userId);
  }

  tombstoneCount() {
    return this.tombstones.length;
  }

  seedDocument(userId: string, overrides: Row = {}) {
    const now = new Date();
    const id = (overrides.id as string | undefined) ?? this.nextId('doc');
    const doc = {
      id,
      user_id: userId,
      fy: '2025-26',
      document_type: 'form16',
      original_filename: 'Form 16.pdf',
      mime_type: 'application/pdf',
      byte_size: 1024,
      sha256_fingerprint: `seed-${id}`,
      ciphertext: 'encrypted-document',
      iv: 'document-iv',
      auth_tag: 'document-auth-tag',
      parse_status: 'needs_confirmation',
      parse_summary: {
        parser: 'deterministic-form16-v1',
        llmUsed: false,
        confirmationStatus: 'pending',
      },
      user_label: null,
      notes: null,
      tags: [],
      vault_status: 'active',
      review_status: 'not_reviewed',
      confirmed_fields: {},
      reviewed_at: null,
      archived_at: null,
      created_at: now,
      updated_at: now,
      ...overrides,
    };
    this.documents.set(id, doc);
    return doc;
  }

  async connect() {
    return new FakeDbClient(this);
  }

  async query(sql: string, params: unknown[] = []): Promise<QueryResult> {
    const normalized = sql.replace(/\s+/g, ' ').trim().toLowerCase();
    if (normalized === 'begin' || normalized === 'commit' || normalized === 'rollback') {
      return rows();
    }
    if (normalized === 'set transaction isolation level read committed') {
      return rows();
    }
    if (normalized.startsWith('set local application_name = ')
      || normalized.startsWith("select set_config('application_name'")) {
      this.userStateContexts.push(normalized);
      return rows();
    }
    if (normalized.startsWith("select set_config('arth.system'")) {
      return rows();
    }

    if (normalized.startsWith('select id from app_users where email = $1')) {
      if (this.transientEmailLookupFailures > 0) {
        this.transientEmailLookupFailures -= 1;
        const error = new Error('database warming up') as Error & { code: string };
        error.code = '57P03';
        throw error;
      }
      const user = this.userByEmail(params[0] as string);
      return rows(user ? [{ id: user.id }] : []);
    }

    if (normalized.startsWith('insert into app_users')) {
      const now = new Date();
      const user: UserRow = {
        id: this.nextId('user'),
        email: params[0] as string,
        name: params[1] as string,
        phone_e164: null,
        avatar_initials: null,
        avatar_color: null,
        password_hash: params[2] as string,
        created_at: now,
        updated_at: now,
        last_seen_at: now,
      };
      this.users.set(user.id, user);
      return rows([user as unknown as Row]);
    }

    if (normalized.startsWith('select id, email, name, phone_e164, avatar_initials, avatar_color, password_hash, created_at from app_users where email = $1')) {
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
        id: params[0] as string,
        user_id: params[1] as string,
        token_hash: params[2] as string,
        expires_at: params[3] as Date,
        revoked_at: null,
        created_at: new Date(),
      };
      this.sessions.set(session.id, session);
      return rows();
    }

    if (normalized.startsWith('select 1 from auth_refresh_sessions where id = $1')) {
      const session = this.sessions.get(params[0] as string);
      return rows(
        session
        && session.user_id === params[1]
        && session.revoked_at === null
        && session.expires_at.getTime() > Date.now()
          ? [{ '?column?': 1 }]
          : [],
      );
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

    if (normalized.startsWith('update auth_refresh_sessions set revoked_at = now() where user_id = $1')) {
      for (const session of this.sessions.values()) {
        if (session.user_id === params[0] && session.revoked_at === null) {
          session.revoked_at = new Date();
        }
      }
      return rows();
    }

    if (normalized.startsWith('delete from app_users where id = $1 returning id')) {
      const userId = params[0] as string;
      if (!this.users.delete(userId)) return rows();
      for (const [sessionId, session] of this.sessions) {
        if (session.user_id === userId) this.sessions.delete(sessionId);
      }
      this.deleteByUser(this.profiles, userId);
      this.deleteByUser(this.taxResults, userId);
      this.deleteByUser(this.doneGaps, userId);
      this.deleteByUser(this.userState, userId);
      this.identities.delete(userId);
      for (const [documentId, document] of this.documents) {
        if (document.user_id === userId) this.documents.delete(documentId);
      }
      return rows([{ id: userId }]);
    }

    if (normalized.startsWith('insert into security_tombstones')) {
      this.tombstones.push({
        deletion_id: params[0],
        anonymous_subject_hash: params[1],
        backup_expires_at: params[2],
      });
      return rows();
    }

    if (normalized.startsWith('select id, email, name, phone_e164, avatar_initials, avatar_color, created_at from app_users where id = $1')) {
      const user = this.users.get(params[0] as string);
      return rows(user ? [user as unknown as Row] : []);
    }

    if (normalized.startsWith('select pan_last4, pan_last_char, pan_consent_version')) {
      const identity = this.identities.get(params[0] as string);
      if (!identity || !identity.pan_ciphertext) return rows();
      return rows([identity]);
    }

    if (normalized.startsWith('select pan_last4, pan_last_char from user_private_identity')) {
      const identity = this.identities.get(params[0] as string);
      if (!identity || !identity.pan_ciphertext) return rows();
      return rows([identity]);
    }

    if (normalized.startsWith('select pan_fingerprint from user_private_identity where user_id = $1')) {
      const identity = this.identities.get(params[0] as string);
      if (!identity || !identity.pan_ciphertext) return rows();
      return rows([{ pan_fingerprint: identity.pan_fingerprint }]);
    }

    if (normalized.startsWith('select user_id from user_private_identity where pan_fingerprint = $1')) {
      const fingerprint = params[0] as string;
      const userId = params[1] as string;
      const identity = [...this.identities.values()].find((candidate) =>
        candidate.pan_fingerprint === fingerprint
        && candidate.user_id !== userId
        && candidate.pan_ciphertext,
      );
      return rows(identity ? [{ user_id: identity.user_id }] : []);
    }

    if (normalized.startsWith('update app_users set name = $1')) {
      const userId = params[4] as string;
      const user = this.users.get(userId);
      if (user) {
        user.name = params[0] as string;
        user.phone_e164 = params[1] as string | null;
        user.avatar_initials = params[2] as string | null;
        user.avatar_color = params[3] as string | null;
        user.updated_at = new Date();
      }
      return rows(user ? [user as unknown as Row] : []);
    }

    if (normalized.startsWith('insert into user_private_identity')) {
      const duplicate = [...this.identities.values()].find((candidate) =>
        candidate.pan_fingerprint === params[6]
        && candidate.user_id !== params[0]
        && candidate.pan_ciphertext,
      );
      if (duplicate) {
        const error = new Error('duplicate PAN fingerprint') as Error & { code: string };
        error.code = '23505';
        throw error;
      }
      const existing = this.identities.get(params[0] as string) ?? {
        user_id: params[0],
        created_at: new Date(),
      };
      this.identities.set(params[0] as string, {
        ...existing,
        pan_ciphertext: params[1],
        pan_iv: params[2],
        pan_auth_tag: params[3],
        pan_last4: params[4],
        pan_last_char: params[5],
        pan_fingerprint: params[6],
        pan_consent_version: params[7],
        pan_consented_at: new Date(),
        pan_deleted_at: null,
        updated_at: new Date(),
      });
      return rows();
    }

    if (normalized.startsWith('update user_private_identity set pan_ciphertext = null')) {
      const identity = this.identities.get(params[0] as string);
      if (identity) {
        Object.assign(identity, {
          pan_ciphertext: null,
          pan_iv: null,
          pan_auth_tag: null,
          pan_last4: null,
          pan_last_char: null,
          pan_fingerprint: null,
          pan_deleted_at: new Date(),
          updated_at: new Date(),
        });
      }
      return rows();
    }

    if (normalized.startsWith('select id, fy, document_type, original_filename')) {
      const docs = [...this.documents.values()]
        .filter((doc) => doc.user_id === params[0] && doc.fy === params[1])
        .sort((a, b) =>
          (b.created_at as Date).getTime() - (a.created_at as Date).getTime(),
        );
      return rows(docs);
    }

    if (normalized.startsWith('insert into tax_documents')) {
      const existing = [...this.documents.values()].find((doc) =>
        doc.user_id === params[0]
        && doc.fy === params[1]
        && doc.document_type === params[2]
        && doc.sha256_fingerprint === params[6],
      );
      const now = new Date();
      const id = existing?.id as string | undefined ?? this.nextId('doc');
      const incomingParseStatus = params[10] as string;
      const incomingParseSummary = JSON.parse(params[11] as string);
      const preserveBetterParse = existing != null
        && ['needs_confirmation', 'parsed'].includes(existing.parse_status as string)
        && !['needs_confirmation', 'parsed'].includes(incomingParseStatus);
      const doc = {
        id,
        user_id: params[0],
        fy: params[1],
        document_type: params[2],
        original_filename: params[3],
        mime_type: params[4],
        byte_size: params[5],
        sha256_fingerprint: params[6],
        ciphertext: params[7],
        iv: params[8],
        auth_tag: params[9],
        parse_status: preserveBetterParse
          ? existing.parse_status
          : incomingParseStatus,
        parse_summary: preserveBetterParse
          ? existing.parse_summary
          : incomingParseSummary,
        user_label: existing?.user_label ?? null,
        notes: existing?.notes ?? null,
        tags: existing?.tags ?? [],
        vault_status: existing?.vault_status ?? 'active',
        review_status: existing?.review_status ?? 'not_reviewed',
        confirmed_fields: existing?.confirmed_fields ?? {},
        reviewed_at: existing?.reviewed_at ?? null,
        archived_at: existing?.archived_at ?? null,
        created_at: existing?.created_at ?? now,
        updated_at: now,
      };
      this.documents.set(id, doc);
      return rows([doc]);
    }

    if (normalized.startsWith('select parse_status, parse_summary')) {
      const doc = this.documents.get(params[0] as string);
      return rows(doc && doc.user_id === params[1] ? [doc] : []);
    }

    if (normalized.startsWith('update tax_documents set parse_status =')) {
      const doc = this.documents.get(params[0] as string);
      if (!doc || doc.user_id !== params[1]) return rows();
      doc.parse_status = 'parsed';
      doc.parse_summary = JSON.parse(params[2] as string);
      doc.confirmed_fields = JSON.parse(params[3] as string);
      doc.document_type = params[4] as string;
      doc.review_status = 'reviewed';
      doc.reviewed_at = new Date();
      doc.updated_at = new Date();
      return rows([doc]);
    }

    if (normalized.startsWith('select user_label, notes, tags, vault_status')) {
      const doc = this.documents.get(params[0] as string);
      return rows(doc && doc.user_id === params[1] ? [doc] : []);
    }

    if (normalized.startsWith('update tax_documents set user_label =')) {
      const doc = this.documents.get(params[0] as string);
      if (!doc || doc.user_id !== params[1]) return rows();
      doc.user_label = params[2] as string | null;
      doc.notes = params[3] as string | null;
      doc.tags = JSON.parse(params[4] as string);
      doc.vault_status = params[5] as string;
      doc.review_status = params[6] as string;
      doc.reviewed_at = params[7] as Date | null;
      doc.archived_at = params[8] as Date | null;
      doc.updated_at = new Date();
      return rows([doc]);
    }

    if (normalized.startsWith('select original_filename, mime_type, ciphertext')) {
      const doc = this.documents.get(params[0] as string);
      return rows(doc && doc.user_id === params[1] ? [doc] : []);
    }

    if (normalized.startsWith('delete from tax_documents where id = $1')) {
      const doc = this.documents.get(params[0] as string);
      if (!doc || doc.user_id !== params[1]) return rows();
      this.documents.delete(params[0] as string);
      return rows([{ document_type: doc.document_type }]);
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

    if (normalized.startsWith('select * from money_goals')) {
      const goals = [...this.moneyGoals.values()]
        .filter((goal) => goal.user_id === params[0])
        .sort((left, right) =>
          (right.updated_at as Date).getTime() - (left.updated_at as Date).getTime());
      return rows(goals);
    }

    if (normalized.startsWith('insert into money_goals')) {
      const now = new Date();
      const goal = {
        id: this.nextId('goal'),
        user_id: params[0],
        name: params[1],
        category: params[2],
        target_amount: params[3],
        current_amount: params[4],
        target_date: params[5],
        monthly_essentials: params[6],
        monthly_family_support: params[7],
        created_at: now,
        updated_at: now,
      };
      this.moneyGoals.set(goal.id, goal);
      return rows([goal]);
    }

    if (normalized.startsWith('update money_goals set')) {
      const goal = this.moneyGoals.get(params[0] as string);
      if (!goal || goal.user_id !== params[1]) return rows();
      Object.assign(goal, {
        name: params[2],
        category: params[3],
        target_amount: params[4],
        current_amount: params[5],
        target_date: params[6],
        monthly_essentials: params[7],
        monthly_family_support: params[8],
        updated_at: new Date(),
      });
      return rows([goal]);
    }

    if (normalized.startsWith('delete from money_goals where id = $1')) {
      const goal = this.moneyGoals.get(params[0] as string);
      if (goal?.user_id === params[1]) this.moneyGoals.delete(params[0] as string);
      return rows();
    }

    if (normalized.startsWith('delete from money_goals where user_id = $1')) {
      for (const [goalId, goal] of this.moneyGoals.entries()) {
        if (goal.user_id === params[0]) this.moneyGoals.delete(goalId);
      }
      return rows();
    }

    if (normalized.startsWith('insert into spend_maps')) {
      const userId = params[0] as string;
      const existing = this.spendMaps.get(userId);
      const salaryCreditDay = params[7] as number | null;
      const clearRequested = params[10] === true;
      const windowStart = new Date(params[1] as string);
      const windowEnd = new Date(params[2] as string);
      const coversSixtyDays =
        windowEnd.getTime() - windowStart.getTime() >= 60 * 24 * 60 * 60 * 1000;
      this.spendMaps.set(params[0] as string, {
        user_id: userId,
        window_start: params[1],
        window_end: params[2],
        generated_at: params[3],
        monthly_income: params[4],
        monthly_spend: params[5],
        realistic_monthly_savings: params[6],
        salary_credit_day: salaryCreditDay ??
            (clearRequested && coversSixtyDays
                ? null
                : (existing?.salary_credit_day ?? null)),
        spend_by_category: JSON.parse(params[8] as string),
        monthly_trend: JSON.parse(params[9] as string),
        updated_at: new Date(),
      });
      return rows();
    }

    if (normalized.startsWith('insert into user_state')) {
      const stateKey = key(params[0], params[1]);
      const existing = this.userState.get(stateKey);
      const isDelete = params.length === 3;
      const incomingUpdatedAt = params[isDelete ? 2 : 5] as Date;
      if (existing
          && (existing.client_updated_at as Date).getTime() > incomingUpdatedAt.getTime()) {
        return rows();
      }
      const item = {
        user_id: params[0],
        namespace: params[1],
        payload_ciphertext: isDelete ? null : params[2],
        payload_iv: isDelete ? null : params[3],
        payload_auth_tag: isDelete ? null : params[4],
        deleted: isDelete,
        client_updated_at: incomingUpdatedAt,
        updated_at: new Date(),
      };
      this.userState.set(stateKey, item);
      return rows([item]);
    }

    if (normalized.startsWith('select namespace, payload_ciphertext, payload_iv, payload_auth_tag, deleted,')) {
      const items = [...this.userState.values()]
        .filter((item) =>
          item.user_id === params[0]
          && (params.length < 2 || item.namespace === params[1]))
        .sort((left, right) =>
          (left.namespace as string).localeCompare(right.namespace as string));
      return rows(items);
    }

    if (normalized.startsWith('delete from spend_maps where user_id = $1')) {
      this.spendMaps.delete(params[0] as string);
      return rows();
    }

    if (normalized.startsWith('delete from user_state where user_id = $1')) {
      if (params.length > 1) {
        this.userState.delete(key(params[0], params[1]));
      } else {
        this.deleteByUser(this.userState, params[0] as string);
      }
      return rows();
    }

    if (normalized.startsWith('select display_name from employer_catalog')) {
      const query = (params[0] as string).toLowerCase();
      const employers = [...this.employers.values()]
        .filter((employer) =>
          (!query || (employer.display_name as string).toLowerCase().includes(query))
          && (employer.approved === true || (employer.usage_count as number) >= 2))
        .map((employer) => ({ display_name: employer.display_name }));
      return rows(employers);
    }

    if (normalized.startsWith('insert into employer_catalog')) {
      const normalizedName = params[0] as string;
      const existing = this.employers.get(normalizedName);
      if (existing) {
        existing.usage_count = (existing.usage_count as number) + 1;
        existing.updated_at = new Date();
        return rows([{ display_name: existing.display_name }]);
      }
      const employer = {
        normalized_name: normalizedName,
        display_name: params[1],
        source: 'user',
        submitted_by: params[2],
        usage_count: 1,
        approved: false,
        created_at: new Date(),
        updated_at: new Date(),
      };
      this.employers.set(normalizedName, employer);
      return rows([{ display_name: employer.display_name }]);
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

    if (normalized.startsWith('delete from tax_documents where user_id = $1')) {
      for (const [docId, doc] of this.documents.entries()) {
        if (doc.user_id === params[0]) this.documents.delete(docId);
      }
      return rows();
    }

    if (normalized.startsWith('insert into device_tokens')) {
      const fingerprint = params[1] as string;
      const existing = this.deviceTokens.get(fingerprint);
      const token = {
        id: existing?.id ?? this.nextId('device'),
        user_id: params[0],
        token_fingerprint: fingerprint,
        token_ciphertext: params[2],
        token_iv: params[3],
        token_auth_tag: params[4],
        platform: params[5],
        created_at: existing?.created_at ?? new Date(),
        last_seen_at: new Date(),
      };
      this.deviceTokens.set(fingerprint, token);
      return rows();
    }

    if (normalized.startsWith('delete from device_tokens where user_id = $1')) {
      const fingerprint = params[1] as string;
      const existing = this.deviceTokens.get(fingerprint);
      if (existing?.user_id === params[0]) {
        this.deviceTokens.delete(fingerprint);
      }
      return rows();
    }

    if (normalized.startsWith('select id, document_type, parse_status, parse_summary')) {
      const wanted = new Set(params[1] as string[]);
      return rows([...this.documents.values()].filter(
        (doc) => doc.user_id === params[0] && wanted.has(doc.id as string),
      ));
    }

    if (normalized.startsWith('insert into offer_comparisons')) {
      const now = new Date();
      const session = {
        id: this.nextId('offer-comparison'),
        user_id: params[0],
        fy: params[1],
        status: 'questions_pending',
        state_encrypted: JSON.parse(params[2] as string),
        advice_fingerprint: null,
        created_at: now,
        updated_at: now,
      };
      this.offerComparisons.set(session.id, session);
      return rows([session]);
    }

    if (normalized.startsWith('insert into offer_comparison_offers')) {
      this.offerComparisonOffers.push({
        comparison_id: params[0],
        document_id: params[1],
        user_id: params[2],
        position: params[3],
      });
      return rows();
    }

    if (normalized.startsWith('select id, status, state_encrypted, advice_fingerprint')
      || normalized.startsWith('select id, status, state_encrypted, created_at')) {
      const session = this.offerComparisons.get(params[0] as string);
      return session && session.user_id === params[1] ? rows([session]) : rows();
    }

    if (normalized.startsWith('update offer_comparisons set status =')) {
      const session = this.offerComparisons.get(params[0] as string);
      if (!session || session.user_id !== params[1]) return rows();
      session.status = params[2];
      session.state_encrypted = JSON.parse(params[3] as string);
      session.advice_fingerprint = params[4];
      session.updated_at = new Date();
      return rows([session]);
    }

    if (normalized.startsWith('insert into user_events')) {
      this.events.push({
        user_id: params[0],
        name: params[1],
        metadata: JSON.parse(params[2] as string),
      });
      return rows();
    }

    if (normalized.startsWith('insert into document_events')) {
      this.events.push({
        user_id: params[0],
        document_id: params[1],
        event_type: params[2],
        metadata: JSON.parse(params[3] as string),
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
    if (prefix === 'doc' || prefix === 'goal' || prefix === 'offer-comparison') {
      return `00000000-0000-4000-8000-${String(this.ids).padStart(12, '0')}`;
    }
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

  it('reports the deployed commit for delivery verification', async () => {
    const previousCommit = process.env.RAILWAY_GIT_COMMIT_SHA;
    process.env.RAILWAY_GIT_COMMIT_SHA = 'abc123';
    let app: Awaited<ReturnType<typeof buildApp>> | undefined;

    try {
      app = await buildApp();
      const response = await app.inject({
        method: 'GET',
        url: '/v1/ping',
      });

      assert.equal(response.statusCode, 200);
      assert.deepEqual(response.json(), {
        ok: true,
        commit: 'abc123',
      });
    } finally {
      await app?.close();
      if (previousCommit === undefined) {
        delete process.env.RAILWAY_GIT_COMMIT_SHA;
      } else {
        process.env.RAILWAY_GIT_COMMIT_SHA = previousCommit;
      }
    }
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
    assert.deepEqual(response.json(), {
      code: 'invalid_request',
      message: 'Invalid request',
      retryable: false,
    });
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
    const revokedAccess = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: bearer(refresh.json().accessToken),
    });
    assert.equal(revokedAccess.statusCode, 401);

    await app.close();
  });

  it('marks transient auth dependency failures as retryable 503 responses', async () => {
    const app = await buildApp();
    fakeDb.failNextEmailLookups(10);

    const response = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-up',
      payload: strongAuthPayload('Retry User', 'retry@example.com'),
    });

    assert.equal(response.statusCode, 503);
    assert.deepEqual(response.json(), {
      code: 'backend_temporarily_unavailable',
      message: 'Service temporarily unavailable',
      retryable: true,
    });
    await app.close();
  });

  it('stores encrypted device tokens and scopes unregister to the owner', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const fcmToken = 'test-fcm-token-that-is-long-enough-123456789';

    const registerAlice = await app.inject({
      method: 'POST',
      url: '/v1/devices',
      headers: bearer(alice.accessToken),
      payload: { fcmToken, platform: 'android' },
    });
    assert.equal(registerAlice.statusCode, 201);

    let stored = fakeDb.rawDeviceTokens();
    assert.equal(stored.length, 1);
    assert.equal(stored[0].user_id, alice.user.id);
    assert.equal(JSON.stringify(stored[0]).includes(fcmToken), false);
    assert.equal(typeof stored[0].token_ciphertext, 'string');

    const registerBob = await app.inject({
      method: 'POST',
      url: '/v1/devices',
      headers: bearer(bob.accessToken),
      payload: { fcmToken, platform: 'android' },
    });
    assert.equal(registerBob.statusCode, 201);
    stored = fakeDb.rawDeviceTokens();
    assert.equal(stored.length, 1);
    assert.equal(stored[0].user_id, bob.user.id);

    const aliceCannotDeleteBobToken = await app.inject({
      method: 'DELETE',
      url: '/v1/devices',
      headers: bearer(alice.accessToken),
      payload: { fcmToken },
    });
    assert.equal(aliceCannotDeleteBobToken.statusCode, 200);
    assert.equal(fakeDb.rawDeviceTokens().length, 1);

    const unregisterBob = await app.inject({
      method: 'DELETE',
      url: '/v1/devices',
      headers: bearer(bob.accessToken),
      payload: { fcmToken },
    });
    assert.equal(unregisterBob.statusCode, 200);
    assert.equal(fakeDb.rawDeviceTokens().length, 0);

    await app.close();
  });

  it('deletes the full account only with explicit confirmation', async () => {
    const app = await buildApp();
    const session = await createSession(app, 'Delete User', 'delete@example.com');

    const rejected = await app.inject({
      method: 'DELETE',
      url: '/v1/account',
      headers: bearer(session.accessToken),
      payload: { confirmation: 'NO' },
    });
    assert.equal(rejected.statusCode, 400);
    assert.equal(fakeDb.hasUser(session.user.id), true);

    const deleted = await app.inject({
      method: 'DELETE',
      url: '/v1/account',
      headers: bearer(session.accessToken),
      payload: { confirmation: 'DELETE' },
    });
    assert.equal(deleted.statusCode, 204);
    assert.equal(fakeDb.hasUser(session.user.id), false);
    assert.equal(fakeDb.tombstoneCount(), 1);

    const staleToken = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: bearer(session.accessToken),
    });
    assert.equal(staleToken.statusCode, 401);
    await app.close();
  });

  it('rejects missing and invalid bearer tokens', async () => {
    const app = await buildApp();

    const missing = await app.inject({ method: 'GET', url: '/v1/me' });
    assert.equal(missing.statusCode, 401);
    assert.deepEqual(missing.json(), {
      code: 'missing_bearer_token',
      message: 'Missing bearer token',
      retryable: false,
    });

    const invalid = await app.inject({
      method: 'GET',
      url: '/v1/me',
      headers: { authorization: 'Bearer not-a-jwt' },
    });
    assert.equal(invalid.statusCode, 401);
    assert.deepEqual(invalid.json(), {
      code: 'invalid_or_expired_access_token',
      message: 'Invalid or expired access token',
      retryable: false,
    });

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

  it('backs up user state by account and rejects stale overwrites', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const currentUpdatedAt = new Date(
      Date.now() - 60 * 60 * 1000,
    ).toISOString();
    const staleUpdatedAt = new Date(
      Date.parse(currentUpdatedAt) - 60 * 60 * 1000,
    ).toISOString();
    const deletedAt = new Date(
      Date.parse(currentUpdatedAt) + 30 * 60 * 1000,
    ).toISOString();

    const saved = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/paycheck-overrides',
      headers: bearer(alice.accessToken),
      payload: {
        payload: '[{"canonicalKey":"basic","amount":80000}]',
        clientUpdatedAt: currentUpdatedAt,
      },
    });
    assert.equal(saved.statusCode, 200);
    assert.equal(
      JSON.stringify(fakeDb.rawUserState()).includes('canonicalKey'),
      false,
    );

    const stale = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/paycheck-overrides',
      headers: bearer(alice.accessToken),
      payload: {
        payload: '[]',
        clientUpdatedAt: staleUpdatedAt,
      },
    });
    assert.equal(stale.statusCode, 200);
    assert.equal(stale.json().item.payload,
      '[{"canonicalKey":"basic","amount":80000}]');

    const aliceState = await app.inject({
      method: 'GET',
      url: '/v1/user-state',
      headers: bearer(alice.accessToken),
    });
    assert.equal(aliceState.statusCode, 200);
    assert.ok(
      fakeDb.rawUserStateContexts().some((query) =>
        query.includes(`arth.${alice.user.id}`)),
    );
    assert.equal(aliceState.json().items.length, 1);
    assert.equal(aliceState.json().items[0].clientUpdatedAt, currentUpdatedAt);

    const bobState = await app.inject({
      method: 'GET',
      url: '/v1/user-state',
      headers: bearer(bob.accessToken),
    });
    assert.deepEqual(bobState.json().items, []);
    assert.ok(Date.parse(bobState.json().serverTime) > 0);

    const unknownNamespace = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/access-token',
      headers: bearer(alice.accessToken),
      payload: {
        payload: 'secret',
        clientUpdatedAt: currentUpdatedAt,
      },
    });
    assert.equal(unknownNamespace.statusCode, 400);

    const missingTimezone = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/tax-year',
      headers: bearer(alice.accessToken),
      payload: {
        payload: 'fy2026_27',
        clientUpdatedAt: '2026-07-29T10:00:00.000',
      },
    });
    assert.equal(missingTimezone.statusCode, 400);

    const futureTimestamp = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const futureClamped = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/tax-year',
      headers: bearer(alice.accessToken),
      payload: {
        payload: 'fy2026_27',
        clientUpdatedAt: futureTimestamp.toISOString(),
      },
    });
    assert.equal(futureClamped.statusCode, 200);
    assert.ok(
      Date.parse(futureClamped.json().item.clientUpdatedAt)
        < futureTimestamp.getTime(),
    );

    const largePayload = 'x'.repeat(200 * 1024);
    const largeState = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/spend-map',
      headers: bearer(alice.accessToken),
      payload: {
        payload: largePayload,
        clientUpdatedAt: currentUpdatedAt,
      },
    });
    assert.equal(largeState.statusCode, 200);
    assert.equal(largeState.json().item.payload.length, largePayload.length);

    const oversizedPayload = 'x'.repeat((16 * 1024 * 1024) + 1);
    const oversizedState = await app.inject({
      method: 'PUT',
      url: '/v1/user-state/spend-map',
      headers: bearer(alice.accessToken),
      payload: {
        payload: oversizedPayload,
        clientUpdatedAt: currentUpdatedAt,
      },
    });
    assert.equal(oversizedState.statusCode, 400);

    const staleDelete = await app.inject({
      method: 'DELETE',
      url: '/v1/user-state/paycheck-overrides',
      headers: bearer(alice.accessToken),
      payload: {
        clientUpdatedAt: staleUpdatedAt,
      },
    });
    assert.equal(staleDelete.statusCode, 200);
    assert.equal(staleDelete.json().item.deleted, false);
    assert.equal(
      staleDelete.json().item.clientUpdatedAt,
      currentUpdatedAt,
    );

    const removed = await app.inject({
      method: 'DELETE',
      url: '/v1/user-state/paycheck-overrides',
      headers: bearer(alice.accessToken),
      payload: {
        clientUpdatedAt: deletedAt,
      },
    });
    assert.equal(removed.statusCode, 200);
    assert.equal(removed.json().item.deleted, true);
    assert.equal(
      removed.json().item.clientUpdatedAt,
      deletedAt,
    );
    assert.ok(Date.parse(removed.json().serverTime) > 0);
    const afterDelete = await app.inject({
      method: 'GET',
      url: '/v1/user-state',
      headers: bearer(alice.accessToken),
    });
    const deletedItem = afterDelete.json().items.find(
      (item: { namespace: string }) =>
        item.namespace === 'paycheck-overrides',
    );
    assert.deepEqual(deletedItem, {
      namespace: 'paycheck-overrides',
      payload: null,
      deleted: true,
      clientUpdatedAt: deletedAt,
    });

    await app.close();
  });

  it('stores optional PAN as encrypted masked account data and isolates it by user', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');

    const missingAuth = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      payload: {
        pan: 'ABCDE1234F',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(missingAuth.statusCode, 401);

    const missingConsent = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(alice.accessToken),
      payload: {
        pan: 'ABCDE1234F',
        consentAccepted: false,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(missingConsent.statusCode, 400);

    const invalidPan = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(alice.accessToken),
      payload: {
        pan: 'not-a-pan',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(invalidPan.statusCode, 400);

    const putPan = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(alice.accessToken),
      payload: {
        pan: 'ABCDE1234F',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(putPan.statusCode, 200);
    assert.equal(putPan.json().pan.maskedPan, '•••••1234F');
    assert.equal(JSON.stringify(putPan.json()).includes('ABCDE1234F'), false);

    const replacePan = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(alice.accessToken),
      payload: {
        pan: 'PQRST6789Z',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(replacePan.statusCode, 409);
    assert.deepEqual(replacePan.json(), {
      message: 'This account already has a different PAN linked',
    });

    const stored = fakeDb.rawIdentity(alice.user.id);
    assert.ok(stored);
    assert.notEqual(stored.pan_ciphertext, 'ABCDE1234F');
    assert.equal(stored.pan_last4, '1234');
    assert.equal(stored.pan_last_char, 'F');

    const aliceProfile = await app.inject({
      method: 'GET',
      url: '/v1/account/profile',
      headers: bearer(alice.accessToken),
    });
    assert.equal(aliceProfile.statusCode, 200);
    assert.equal(aliceProfile.json().pan.maskedPan, '•••••1234F');
    assert.equal(JSON.stringify(aliceProfile.json()).includes('ABCDE1234F'), false);

    const bobProfile = await app.inject({
      method: 'GET',
      url: '/v1/account/profile',
      headers: bearer(bob.accessToken),
    });
    assert.equal(bobProfile.statusCode, 200);
    assert.equal(bobProfile.json().pan.status, 'missing');

    const duplicatePan = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(bob.accessToken),
      payload: {
        pan: 'ABCDE1234F',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(duplicatePan.statusCode, 409);
    assert.deepEqual(duplicatePan.json(), {
      message: 'This PAN is already linked to another ARTH account',
    });

    await app.close();
  });

  it('updates account display name and deletes PAN via clear data', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');

    const patchName = await app.inject({
      method: 'PATCH',
      url: '/v1/account/profile',
      headers: bearer(alice.accessToken),
      payload: { name: 'Alice Rao' },
    });
    assert.equal(patchName.statusCode, 200);
    assert.equal(patchName.json().user.name, 'Alice Rao');

    const patchDetails = await app.inject({
      method: 'PATCH',
      url: '/v1/account/profile',
      headers: bearer(alice.accessToken),
      payload: {
        phoneNumber: '+919749452397',
        avatarInitials: 'AR',
        avatarColor: 'teal',
      },
    });
    assert.equal(patchDetails.statusCode, 200);
    assert.equal(patchDetails.json().user.phoneNumber, '+919749452397');
    assert.equal(patchDetails.json().user.avatarInitials, 'AR');
    assert.equal(patchDetails.json().user.avatarColor, 'teal');

    const putPan = await app.inject({
      method: 'PUT',
      url: '/v1/account/pan',
      headers: bearer(alice.accessToken),
      payload: {
        pan: 'ABCDE1234F',
        consentAccepted: true,
        consentVersion: 'pan-v1',
      },
    });
    assert.equal(putPan.statusCode, 200);

    const patchAfterPan = await app.inject({
      method: 'PATCH',
      url: '/v1/account/profile',
      headers: bearer(alice.accessToken),
      payload: { name: 'Alice Sharma' },
    });
    assert.equal(patchAfterPan.statusCode, 200);
    assert.equal(patchAfterPan.json().pan.status, 'present');
    assert.equal(patchAfterPan.json().pan.maskedPan, '•••••1234F');

    const clear = await app.inject({
      method: 'DELETE',
      url: '/v1/profile',
      headers: bearer(alice.accessToken),
    });
    assert.equal(clear.statusCode, 204);

    const account = await app.inject({
      method: 'GET',
      url: '/v1/account/profile',
      headers: bearer(alice.accessToken),
    });
    assert.equal(account.statusCode, 200);
    assert.equal(account.json().pan.status, 'missing');
    const clearedState = fakeDb.rawUserState()
      .filter((item) => item.user_id === alice.user.id);
    // One tombstone per durable namespace (see userStateNamespaces).
    assert.equal(clearedState.length, 15);
    assert.ok(clearedState.every((item) =>
      item.deleted === true && item.payload_ciphertext === null));

    await app.close();
  });

  it('clears a stale payday only after a 60-day salary-free scan', async () => {
    const app = await buildApp();
    const session = await createSession(app, 'Alice', 'alice@example.com');
    const base = {
      generatedAt: '2026-07-30T00:00:00.000Z',
      monthlyIncome: 50000,
      monthlySpend: 20000,
      realisticMonthlySavings: 30000,
      spendByCategory: { groceries: 5000 },
      monthlyTrend: [],
    };

    const detected = await app.inject({
      method: 'POST',
      url: '/v1/spend-map',
      headers: bearer(session.accessToken),
      payload: {
        ...base,
        windowStart: '2026-05-01T00:00:00.000Z',
        windowEnd: '2026-07-30T00:00:00.000Z',
        salaryCreditDay: 28,
      },
    });
    assert.equal(detected.statusCode, 200);
    assert.equal(fakeDb.rawSpendMap(session.user.id)?.salary_credit_day, 28);

    const shortScan = await app.inject({
      method: 'POST',
      url: '/v1/spend-map',
      headers: bearer(session.accessToken),
      payload: {
        ...base,
        windowStart: '2026-07-01T00:00:00.000Z',
        windowEnd: '2026-07-30T00:00:00.000Z',
        clearSalaryCreditDay: true,
      },
    });
    assert.equal(shortScan.statusCode, 200);
    assert.equal(fakeDb.rawSpendMap(session.user.id)?.salary_credit_day, 28);

    const fullScan = await app.inject({
      method: 'POST',
      url: '/v1/spend-map',
      headers: bearer(session.accessToken),
      payload: {
        ...base,
        windowStart: '2026-05-01T00:00:00.000Z',
        windowEnd: '2026-07-30T00:00:00.000Z',
        clearSalaryCreditDay: true,
      },
    });
    assert.equal(fullScan.statusCode, 200);
    assert.equal(fakeDb.rawSpendMap(session.user.id)?.salary_credit_day, null);

    await app.close();
  });

  it('stores owner-scoped money goals and learns repeated custom employers', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const goalPayload = {
      name: 'Support my parents',
      category: 'family',
      targetAmount: 240000,
      currentAmount: 60000,
      targetDate: '2027-07-01',
      monthlyEssentials: 18000,
      monthlyFamilySupport: 5000,
    };

    const created = await app.inject({
      method: 'POST',
      url: '/v1/money-goals',
      headers: bearer(alice.accessToken),
      payload: goalPayload,
    });
    assert.equal(created.statusCode, 201);
    assert.equal(created.json().goal.name, goalPayload.name);
    const goalId = created.json().goal.id as string;

    const aliceGoals = await app.inject({
      method: 'GET',
      url: '/v1/money-goals',
      headers: bearer(alice.accessToken),
    });
    assert.equal(aliceGoals.statusCode, 200);
    assert.equal(aliceGoals.json().goals.length, 1);

    const spendMap = await app.inject({
      method: 'POST',
      url: '/v1/spend-map',
      headers: bearer(alice.accessToken),
      payload: {
        windowStart: '2026-05-01T00:00:00.000Z',
        windowEnd: '2026-07-24T00:00:00.000Z',
        generatedAt: '2026-07-24T00:00:00.000Z',
        monthlyIncome: 109412,
        monthlySpend: 50969,
        realisticMonthlySavings: 58443,
        spendByCategory: { bills: 12000, groceries: 8000 },
        monthlyTrend: [{
          month: '2026-07-01T00:00:00.000Z',
          spent: 50969,
          income: 109412,
        }],
      },
    });
    assert.equal(spendMap.statusCode, 200);

    const bobUpdate = await app.inject({
      method: 'PUT',
      url: `/v1/money-goals/${goalId}`,
      headers: bearer(bob.accessToken),
      payload: { ...goalPayload, name: 'Not Bob\'s goal' },
    });
    assert.equal(bobUpdate.statusCode, 404);

    for (const session of [alice, bob]) {
      const customEmployer = await app.inject({
        method: 'POST',
        url: '/v1/employers',
        headers: bearer(session.accessToken),
        payload: { name: 'Durgapur Product Works' },
      });
      assert.equal(customEmployer.statusCode, 201);
    }

    const search = await app.inject({
      method: 'GET',
      url: '/v1/employers?q=Durgapur',
    });
    assert.equal(search.statusCode, 200);
    assert.deepEqual(search.json().employers, ['Durgapur Product Works']);

    await app.close();
  });

  it('stores tax documents encrypted, owner-scoped, and wiped by clear data', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const documentBytes = Buffer.from('%PDF-1.4 ARTH Form 16 fixture\n');

    const missingAuth = await app.inject({
      method: 'GET',
      url: '/v1/documents',
    });
    assert.equal(missingAuth.statusCode, 401);

    const upload = await app.inject({
      method: 'POST',
      url: '/v1/documents',
      headers: {
        ...bearer(alice.accessToken),
        'content-type': `multipart/form-data; boundary=${multipartBoundary}`,
      },
      payload: multipartPayload({
        documentType: 'form16',
        filename: 'Form 16 FY.pdf',
        mimeType: 'application/pdf',
        bytes: documentBytes,
      }),
    });
    assert.equal(upload.statusCode, 200);
    const uploaded = upload.json().document as {
      id: string;
      documentType: string;
      originalFilename: string;
      mimeType: string;
      byteSize: number;
      parseSummary: { llmUsed: boolean; insight: string };
    };
    assert.equal(uploaded.documentType, 'form16');
    assert.equal(uploaded.originalFilename, 'Form 16 FY.pdf');
    assert.equal(uploaded.mimeType, 'application/pdf');
    assert.equal(uploaded.byteSize, documentBytes.length);
    assert.equal(uploaded.parseSummary.llmUsed, false);
    assert.equal(JSON.stringify(upload.json()).includes(documentBytes.toString()), false);
    assert.equal(JSON.stringify(upload.json()).includes('ciphertext'), false);

    const stored = fakeDb.rawDocument(uploaded.id);
    assert.ok(stored);
    assert.notEqual(stored.ciphertext, documentBytes.toString());
    assert.equal(JSON.stringify(stored).includes(documentBytes.toString()), false);

    const aliceList = await app.inject({
      method: 'GET',
      url: '/v1/documents',
      headers: bearer(alice.accessToken),
    });
    assert.equal(aliceList.statusCode, 200);
    assert.equal(aliceList.json().documents.length, 1);
    assert.equal(aliceList.json().summary.active, 1);
    assert.equal(aliceList.json().summary.archived, 0);

    const patch = await app.inject({
      method: 'PATCH',
      url: `/v1/documents/${uploaded.id}`,
      headers: bearer(alice.accessToken),
      payload: {
        userLabel: 'FY Form 16',
        notes: 'Reviewed with payroll portal.',
        tags: ['salary', 'form16'],
        reviewStatus: 'needs_review',
      },
    });
    assert.equal(patch.statusCode, 200);
    assert.equal(patch.json().document.userLabel, 'FY Form 16');
    assert.deepEqual(patch.json().document.tags, ['salary', 'form16']);

    const bobPatch = await app.inject({
      method: 'PATCH',
      url: `/v1/documents/${uploaded.id}`,
      headers: bearer(bob.accessToken),
      payload: { userLabel: 'Bob label' },
    });
    assert.equal(bobPatch.statusCode, 404);

    const archive = await app.inject({
      method: 'PATCH',
      url: `/v1/documents/${uploaded.id}`,
      headers: bearer(alice.accessToken),
      payload: { vaultStatus: 'archived' },
    });
    assert.equal(archive.statusCode, 200);
    assert.equal(archive.json().document.vaultStatus, 'archived');
    assert.ok(fakeDb.rawDocument(uploaded.id)?.ciphertext);

    const archivedList = await app.inject({
      method: 'GET',
      url: '/v1/documents',
      headers: bearer(alice.accessToken),
    });
    assert.equal(archivedList.json().summary.active, 0);
    assert.equal(archivedList.json().summary.archived, 1);

    const restore = await app.inject({
      method: 'PATCH',
      url: `/v1/documents/${uploaded.id}`,
      headers: bearer(alice.accessToken),
      payload: { vaultStatus: 'active', reviewStatus: 'reviewed' },
    });
    assert.equal(restore.statusCode, 200);
    assert.equal(restore.json().document.vaultStatus, 'active');
    assert.equal(restore.json().document.reviewStatus, 'reviewed');

    const bobList = await app.inject({
      method: 'GET',
      url: '/v1/documents',
      headers: bearer(bob.accessToken),
    });
    assert.equal(bobList.statusCode, 200);
    assert.equal(bobList.json().documents.length, 0);

    const bobDownload = await app.inject({
      method: 'GET',
      url: `/v1/documents/${uploaded.id}/download`,
      headers: bearer(bob.accessToken),
    });
    assert.equal(bobDownload.statusCode, 404);

    const aliceDownload = await app.inject({
      method: 'GET',
      url: `/v1/documents/${uploaded.id}/download`,
      headers: bearer(alice.accessToken),
    });
    assert.equal(aliceDownload.statusCode, 200);
    assert.equal(aliceDownload.headers['content-type'], 'application/pdf');
    assert.deepEqual(aliceDownload.rawPayload, documentBytes);

    const clear = await app.inject({
      method: 'DELETE',
      url: '/v1/profile',
      headers: bearer(alice.accessToken),
    });
    assert.equal(clear.statusCode, 204);

    const afterClear = await app.inject({
      method: 'GET',
      url: '/v1/documents',
      headers: bearer(alice.accessToken),
    });
    assert.equal(afterClear.statusCode, 200);
    assert.equal(afterClear.json().documents.length, 0);

    await app.close();
  });

  it('persists parsed payslip fields through upload, review, and confirmation', async () => {
    const previousGeminiKey = process.env.GEMINI_API_KEY;
    const previousSarvamKey = process.env.SARVAM_API_KEY;
    delete process.env.GEMINI_API_KEY;
    delete process.env.SARVAM_API_KEY;
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const payslipBytes = Buffer.concat([
      Buffer.from('synthetic payslip image'),
      Buffer.alloc(150 * 1024),
    ]);
    const ocrText = `
      PAYSLIP FOR MAY-2023 PAID IN JUN-2023
      NAME/NAME: EXAMPLE EMPLOYEE

      PAYMENTS (TAXABLE)
      BASIC 66703
      DA 25147
      PERKS 15877
      TOTAL EARNINGS 109412

      RECOVERIES (NON-TAXABLE)
      CPF PC 11022
      VPF 25000
      ITAX 11059
      TOTAL DEDUCTIONS 50969

      NET PAY 58443
    `;

    const upload = await app.inject({
      method: 'POST',
      url: '/v1/documents',
      headers: {
        ...bearer(alice.accessToken),
        'content-type': `multipart/form-data; boundary=${multipartBoundary}`,
      },
      payload: multipartPayload({
        documentType: 'payslip',
        filename: 'May payslip.jpg',
        mimeType: 'image/jpeg',
        bytes: payslipBytes,
        ocrText,
      }),
    });
    assert.equal(upload.statusCode, 200);
    const uploaded = upload.json().document as {
      id: string;
      parseStatus: string;
      parseSummary: {
        parser: string;
        extractedFields: {
          grossEarnings: number;
          totalDeductions: number;
          netSalary: number;
        };
      };
    };
    assert.equal(uploaded.parseStatus, 'needs_confirmation');
    assert.equal(uploaded.parseSummary.parser, 'deterministic-payslip-v2');
    assert.equal(uploaded.parseSummary.extractedFields.grossEarnings, 109412);
    assert.equal(uploaded.parseSummary.extractedFields.totalDeductions, 50969);
    assert.equal(uploaded.parseSummary.extractedFields.netSalary, 58443);

    const storedBeforeConfirmation = fakeDb.rawDocument(uploaded.id);
    assert.ok(storedBeforeConfirmation);
    assert.equal(
      Object.hasOwn(storedBeforeConfirmation.parse_summary, 'extractedFields'),
      false,
    );
    assert.ok(storedBeforeConfirmation.parse_summary.encryptedExtractedFields);
    assert.equal(JSON.stringify(storedBeforeConfirmation).includes(ocrText), false);

    const listed = await app.inject({
      method: 'GET',
      url: '/v1/documents',
      headers: bearer(alice.accessToken),
    });
    assert.equal(listed.statusCode, 200);
    assert.equal(
      listed.json().documents[0].parseSummary.extractedFields.netSalary,
      58443,
    );

    const transientReupload = await app.inject({
      method: 'POST',
      url: '/v1/documents',
      headers: {
        ...bearer(alice.accessToken),
        'content-type': `multipart/form-data; boundary=${multipartBoundary}`,
      },
      payload: multipartPayload({
        documentType: 'payslip',
        filename: 'May payslip.jpg',
        mimeType: 'image/jpeg',
        bytes: payslipBytes,
      }),
    });
    assert.equal(transientReupload.statusCode, 200);
    assert.equal(
      transientReupload.json().document.parseStatus,
      'needs_confirmation',
    );
    assert.equal(
      transientReupload.json().document.parseSummary.extractedFields.netSalary,
      58443,
    );

    const confirm = await app.inject({
      method: 'POST',
      url: `/v1/documents/${uploaded.id}/confirm`,
      headers: bearer(alice.accessToken),
      payload: {},
    });
    assert.equal(confirm.statusCode, 200);
    assert.equal(confirm.json().document.parseStatus, 'parsed');
    assert.equal(confirm.json().document.confirmedFields.netSalary, 58443);

    const storedAfterConfirmation = fakeDb.rawDocument(uploaded.id);
    assert.equal(storedAfterConfirmation?.parse_status, 'parsed');
    assert.equal(storedAfterConfirmation?.confirmed_fields.netSalary, 58443);

    await app.close();
    if (previousGeminiKey) process.env.GEMINI_API_KEY = previousGeminiKey;
    if (previousSarvamKey) process.env.SARVAM_API_KEY = previousSarvamKey;
  });

  it('confirms parsed document fields only for the owner and pending documents', async () => {
    const { encryptDocument } = await import('../src/security.js');
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const extractedFields = {
      employerName: 'Example Technologies Private Limited',
      employerTan: 'ABCD12345E',
      grossSalary: 1850000,
      taxDeductedAtSource: 125500,
      panMatchStatus: 'matches_vault',
    };
    const encryptedExtractedFields = encryptDocument(
      Buffer.from(JSON.stringify(extractedFields), 'utf8'),
    );
    const pending = fakeDb.seedDocument(alice.user.id, {
      id: '00000000-0000-4000-8000-000000000091',
      parse_status: 'needs_confirmation',
      parse_summary: {
        parser: 'deterministic-form16-v1',
        llmUsed: false,
        confirmationStatus: 'pending',
        encryptedExtractedFields,
      },
    });
    const wrongStatus = fakeDb.seedDocument(alice.user.id, {
      id: '00000000-0000-4000-8000-000000000092',
      parse_status: 'metadata_ready',
    });

    const bobConfirm = await app.inject({
      method: 'POST',
      url: `/v1/documents/${pending.id}/confirm`,
      headers: bearer(bob.accessToken),
    });
    assert.equal(bobConfirm.statusCode, 404);

    const conflict = await app.inject({
      method: 'POST',
      url: `/v1/documents/${wrongStatus.id}/confirm`,
      headers: bearer(alice.accessToken),
    });
    assert.equal(conflict.statusCode, 409);

    const confirm = await app.inject({
      method: 'POST',
      url: `/v1/documents/${pending.id}/confirm`,
      headers: bearer(alice.accessToken),
    });
    assert.equal(confirm.statusCode, 200);
    assert.equal(confirm.json().document.parseStatus, 'parsed');
    assert.equal(
      confirm.json().document.parseSummary.extractedFields.grossSalary,
      1850000,
    );
    assert.equal(confirm.json().document.confirmedFields.grossSalary, 1850000);
    assert.equal(JSON.stringify(confirm.json()).includes('encryptedExtractedFields'), false);
    assert.equal(JSON.stringify(confirm.json()).includes(encryptedExtractedFields.ciphertext), false);

    const stored = fakeDb.rawDocument(pending.id);
    assert.ok(stored);
    assert.equal(stored.parse_status, 'parsed');
    const storedSummary = stored.parse_summary as Record<string, unknown>;
    assert.equal(Object.hasOwn(storedSummary, 'extractedFields'), false);
    assert.equal(Object.hasOwn(storedSummary, 'encryptedExtractedFields'), true);
    assert.equal(JSON.stringify(storedSummary).includes('1850000'), false);
    assert.equal(JSON.stringify(storedSummary).includes('Example Technologies'), false);
    assert.equal(JSON.stringify(stored.parse_summary).includes('confirmedFields'), false);
    assert.equal((stored.confirmed_fields as Row).grossSalary, 1850000);
    assert.deepEqual(
      storedSummary.confirmedFieldKeys,
      Object.keys(extractedFields),
    );

    await app.close();
  });

  it('accepts validated manual details for an unparsed payslip', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const payslip = fakeDb.seedDocument(alice.user.id, {
      id: '00000000-0000-4000-8000-000000000093',
      document_type: 'payslip',
      original_filename: 'salary.jpg',
      mime_type: 'image/jpeg',
      parse_status: 'metadata_ready',
      parse_summary: {
        parser: 'gemini-payslip-v1',
        insight: 'Manual review is required.',
      },
    });
    const fields = {
      employerName: 'Example Steel Limited',
      payPeriod: 'May 2023',
      currency: 'INR',
      earnings: [
        {
          label: 'Basic',
          amount: 66703,
          classification: 'other',
          confidence: 'high',
        },
      ],
      deductions: [
        {
          label: 'Total recoveries',
          amount: 50969,
          classification: 'other',
          confidence: 'high',
        },
      ],
      grossEarnings: 109412,
      totalDeductions: 50969,
      netSalary: 58443,
    };

    const confirm = await app.inject({
      method: 'POST',
      url: `/v1/documents/${payslip.id}/confirm`,
      headers: bearer(alice.accessToken),
      payload: { fields },
    });
    assert.equal(confirm.statusCode, 200);
    assert.equal(confirm.json().document.parseStatus, 'parsed');
    assert.equal(confirm.json().document.confirmedFields.netSalary, 58443);
    assert.equal(confirm.json().document.parseSummary.manualEntry, true);

    const invalid = fakeDb.seedDocument(alice.user.id, {
      id: '00000000-0000-4000-8000-000000000094',
      document_type: 'payslip',
      parse_status: 'metadata_ready',
      parse_summary: { parser: 'gemini-payslip-v1' },
    });
    const rejected = await app.inject({
      method: 'POST',
      url: `/v1/documents/${invalid.id}/confirm`,
      headers: bearer(alice.accessToken),
      payload: {
        fields: {
          ...fields,
          netSalary: 60000,
        },
      },
    });
    assert.equal(rejected.statusCode, 400);

    await app.close();
  });

  it('extracts deterministic Form 16 fields without returning raw PAN', () => {
    const fields = parseForm16Text(
      [
        'Employer Name: Example Technologies Private Limited',
        'TAN: ABCD12345E',
        'Employer PAN: ABCDE1234F',
        'Employee PAN: fghij5678k',
        'Financial Year: 2025-26',
        'Assessment Year: 2026-27',
        'Gross Salary: Rs. 18,50,000',
        'Standard Deduction: Rs. 75,000',
        'Chapter VI-A deductions: Rs. 1,50,000',
        'Tax deducted at source: Rs. 1,25,500',
        'Taxable income: Rs. 15,75,000',
      ].join('\n'),
      { last4: '5678', lastChar: 'K' },
    );

    assert.equal(fields.employerTan, 'ABCD12345E');
    assert.equal(fields.panMatchStatus, 'matches_vault');
    assert.equal(fields.grossSalary, 1850000);
    assert.equal(fields.taxDeductedAtSource, 125500);
    assert.equal(JSON.stringify(fields).includes('ABCDE1234F'), false);
    assert.equal(JSON.stringify(fields).includes('FGHIJ5678K'), false);
  });

  it('keeps plugin errors sanitized while preserving 413 and 429 status codes', async () => {
    const app = await buildApp();

    const tooLarge = await app.inject({
      method: 'POST',
      url: '/v1/auth/sign-up',
      payload: { blob: 'x'.repeat(110 * 1024) },
    });
    assert.equal(tooLarge.statusCode, 413);
    assert.deepEqual(tooLarge.json(), {
      code: 'request_body_too_large',
      message: 'Request body too large',
      retryable: false,
    });

    let limitedStatus = 0;
    for (let i = 0; i < 25; i += 1) {
      const response = await app.inject({
        method: 'POST',
        url: '/v1/auth/sign-in',
        payload: { email: `nobody-${i}@example.com`, password: 'WrongPass9' },
      });
      limitedStatus = response.statusCode;
      if (limitedStatus === 429) {
        assert.deepEqual(response.json(), {
          code: 'too_many_requests',
          message: 'Too many requests',
          retryable: false,
        });
        break;
      }
    }
    assert.equal(limitedStatus, 429);

    await app.close();
  });

  async function seedOfferLetter(
    userId: string,
    id: string,
    fields: Record<string, unknown>,
  ) {
    const { encryptDocument } = await import('../src/security.js');
    return fakeDb.seedDocument(userId, {
      id,
      document_type: 'offerLetter',
      parse_status: 'needs_confirmation',
      parse_summary: {
        parser: 'gemini-offer-letter-v1',
        llmUsed: true,
        confirmationStatus: 'pending',
        encryptedExtractedFields: encryptDocument(
          Buffer.from(JSON.stringify({
            employerName: 'Employer',
            roleTitle: 'Analyst',
            currency: 'INR',
            annualCtc: null,
            fixedAnnualPay: null,
            variableAnnualPay: null,
            joiningBonus: null,
            components: [],
            warnings: [],
            questionsForUser: [],
            ...fields,
          }), 'utf8'),
        ),
      },
    });
  }

  it('compares stored offer letters and asks at most five questions', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const zeta = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a1',
      {
        employerName: 'Zeta',
        annualCtc: 1_500_000,
        fixedAnnualPay: 1_000_000,
        variableAnnualPay: 500_000,
      },
    );
    const orbit = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a2',
      {
        employerName: 'Orbit',
        annualCtc: 1_400_000,
        fixedAnnualPay: 1_250_000,
        variableAnnualPay: 150_000,
      },
    );

    const created = await app.inject({
      method: 'POST',
      url: '/v1/offers/compare',
      headers: bearer(alice.accessToken),
      payload: { documentIds: [zeta.id, orbit.id] },
    });

    assert.equal(created.statusCode, 201);
    const body = created.json().comparison;
    assert.equal(body.rankedDocumentIds[0], orbit.id);
    assert.equal(body.largestCtcIsNotBestGuaranteed, true);
    assert.ok(body.questions.length <= 5);
    // The rationale for choosing each question is briefing material for the
    // advice call, not something the candidate reads.
    assert.ok(body.questions.every((question: Record<string, unknown>) =>
      question.because === undefined));

    await app.close();
  });

  it('refuses to compare a document that is not an offer letter', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const offer = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a3',
      { fixedAnnualPay: 1_000_000 },
    );
    const form16 = fakeDb.seedDocument(alice.user.id, {
      id: '00000000-0000-4000-8000-0000000000a4',
    });

    const response = await app.inject({
      method: 'POST',
      url: '/v1/offers/compare',
      headers: bearer(alice.accessToken),
      payload: { documentIds: [offer.id, form16.id] },
    });

    assert.equal(response.statusCode, 409);
    await app.close();
  });

  it('does not compare another account\'s offer letters', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const bob = await createSession(app, 'Bob', 'bob@example.com');
    const aliceOffer = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a5',
      { fixedAnnualPay: 1_000_000 },
    );

    const response = await app.inject({
      method: 'POST',
      url: '/v1/offers/compare',
      headers: bearer(bob.accessToken),
      payload: { documentIds: [aliceOffer.id] },
    });

    assert.equal(response.statusCode, 404);
    await app.close();
  });

  it('rejects an answer to a question this comparison never asked', async () => {
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const offer = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a6',
      { fixedAnnualPay: 1_000_000 },
    );
    const created = await app.inject({
      method: 'POST',
      url: '/v1/offers/compare',
      headers: bearer(alice.accessToken),
      payload: { documentIds: [offer.id] },
    });
    const comparisonId = created.json().comparison.id;

    const response = await app.inject({
      method: 'POST',
      url: `/v1/offers/compare/${comparisonId}/answers`,
      headers: bearer(alice.accessToken),
      // A single offer never gets the leverage question, so answering it would
      // brief the advice call with a premise the comparison does not support.
      payload: { answers: [{ id: 'leverage', answer: 'Both of them know' }] },
    });

    assert.equal(response.statusCode, 400);
    await app.close();
  });

  it('keeps the answers when advice is unavailable, so they are not re-entered', async () => {
    const previousKey = process.env.GEMINI_API_KEY;
    delete process.env.GEMINI_API_KEY;
    const app = await buildApp();
    const alice = await createSession(app, 'Alice', 'alice@example.com');
    const offer = await seedOfferLetter(
      alice.user.id,
      '00000000-0000-4000-8000-0000000000a7',
      { fixedAnnualPay: 1_000_000, joiningBonus: 200_000 },
    );
    const created = await app.inject({
      method: 'POST',
      url: '/v1/offers/compare',
      headers: bearer(alice.accessToken),
      payload: { documentIds: [offer.id] },
    });
    const comparisonId = created.json().comparison.id;

    const answered = await app.inject({
      method: 'POST',
      url: `/v1/offers/compare/${comparisonId}/answers`,
      headers: bearer(alice.accessToken),
      payload: { answers: [{ id: 'tenure', answer: 'three_plus' }] },
    });
    assert.equal(answered.statusCode, 503);

    const reread = await app.inject({
      method: 'GET',
      url: `/v1/offers/compare/${comparisonId}`,
      headers: bearer(alice.accessToken),
    });
    assert.equal(reread.statusCode, 200);
    assert.deepEqual(reread.json().comparison.answers, [
      { id: 'tenure', answer: 'three_plus' },
    ]);
    assert.equal(reread.json().comparison.advice, null);

    await app.close();
    if (previousKey) process.env.GEMINI_API_KEY = previousKey;
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
  return response.json() as {
    accessToken: string;
    refreshToken: string;
    user: { id: string; email: string; name: string; createdAt: string };
  };
}

function bearer(accessToken: string) {
  return { authorization: `Bearer ${accessToken}` };
}

const multipartBoundary = 'arth-test-boundary';

function multipartPayload(input: {
  documentType: string;
  filename: string;
  mimeType: string;
  bytes: Buffer;
  ocrText?: string;
}) {
  const textFields = [
    `--${multipartBoundary}`,
    'Content-Disposition: form-data; name="documentType"',
    '',
    input.documentType,
    ...(input.ocrText ? [
      `--${multipartBoundary}`,
      'Content-Disposition: form-data; name="ocrText"',
      '',
      input.ocrText,
    ] : []),
  ];
  return Buffer.concat([
    Buffer.from(
      [
        ...textFields,
        `--${multipartBoundary}`,
        `Content-Disposition: form-data; name="file"; filename="${input.filename}"`,
        `Content-Type: ${input.mimeType}`,
        '',
        '',
      ].join('\r\n'),
    ),
    input.bytes,
    Buffer.from(`\r\n--${multipartBoundary}--\r\n`),
  ]);
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
    actual_basic_salary: params[26] ?? null,
    actual_hra_received: params[27] ?? null,
    actual_professional_tax: params[28] ?? null,
    health_insurance_self_premium: params[29] ?? null,
    health_insurance_parents_premium: params[30] ?? null,
    savings_interest: params[31] ?? null,
    fd_interest: params[32] ?? null,
    employer_nps_contribution: params[33] ?? null,
    donation_deduction_rate_percent: params[34] ?? null,
  };
}
