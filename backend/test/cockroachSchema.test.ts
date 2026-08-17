import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { describe, it } from 'node:test';

const schema = await readFile(
  new URL('../sql/cockroach/001_secure_schema.sql', import.meta.url),
  'utf8',
);
const durableStateSchema = await readFile(
  new URL('../sql/cockroach/002_durable_user_state.sql', import.meta.url),
  'utf8',
);
const durableStateHardening = await readFile(
  new URL('../sql/cockroach/003_durable_user_state_hardening.sql', import.meta.url),
  'utf8',
);
const postgresDurableStateSchema = await readFile(
  new URL('../sql/016_durable_user_state.sql', import.meta.url),
  'utf8',
);
const postgresDurableStateHardening = await readFile(
  new URL('../sql/017_durable_user_state_hardening.sql', import.meta.url),
  'utf8',
);
const postgresTenantRls = await readFile(
  new URL('../sql/019_tenant_rls.sql', import.meta.url),
  'utf8',
);
const verifier = await readFile(
  new URL('../src/scripts/verify-cockroach.ts', import.meta.url),
  'utf8',
);
const aiSpendCockroach = await readFile(
  new URL('../sql/cockroach/004_ai_spend_and_merchant_cache.sql', import.meta.url),
  'utf8',
);
const aiSpendPostgres = await readFile(
  new URL('../sql/018_ai_spend_and_merchant_cache.sql', import.meta.url),
  'utf8',
);
const offerComparisonsPostgres = await readFile(
  new URL('../sql/020_offer_comparisons.sql', import.meta.url),
  'utf8',
);
const offerComparisonsCockroach = await readFile(
  new URL('../sql/cockroach/005_offer_comparisons.sql', import.meta.url),
  'utf8',
);

describe('Cockroach secure schema', () => {
  it('contains required domain schemas and ownership controls', () => {
    for (const name of [
      'auth',
      'privacy',
      'profile',
      'vault',
      'payroll',
      'finance',
      'tax',
      'goals',
      'reference',
      'ops',
    ]) {
      assert.match(schema, new RegExp(`CREATE SCHEMA IF NOT EXISTS ${name};`));
    }
    assert.match(schema, /FORCE ROW LEVEL SECURITY/g);
    assert.match(schema, /FOREIGN KEY \(user_id, document_id\)/);
    assert.match(schema, /UNIQUE \(user_id, source_fingerprint\)/);
    assert.match(schema, /payload_ciphertext\s+BYTES NOT NULL/);
  });

  it('does not store raw SMS or API secrets', () => {
    assert.doesNotMatch(schema, /raw_sms|sms_body|api_key|provider_secret/i);
  });

  it('encrypts durable user state at rest', () => {
    assert.match(durableStateSchema, /payload_ciphertext\s+STRING/);
    assert.match(durableStateSchema, /payload_iv\s+STRING/);
    assert.match(durableStateSchema, /payload_auth_tag\s+STRING/);
    assert.match(durableStateSchema, /deleted\s+BOOL NOT NULL DEFAULT false/);
    assert.match(
      durableStateSchema,
      /ALTER TABLE user_state FORCE ROW LEVEL SECURITY/,
    );
    assert.match(
      durableStateSchema,
      /CREATE POLICY app_user_isolation ON user_state/,
    );
    assert.match(
      durableStateSchema,
      /GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE user_state TO arth_app_runtime/,
    );
    assert.match(verifier, /'public\.user_state'/);
    assert.match(postgresDurableStateHardening, /FORCE ROW LEVEL SECURITY/);
    assert.match(postgresDurableStateHardening, /app_user_state_isolation/);
    assert.match(postgresDurableStateHardening, /REVOKE ALL ON TABLE user_state FROM PUBLIC/);
    assert.match(durableStateHardening, /length\(namespace\) <= 64/);
    assert.match(postgresDurableStateHardening, /length\(namespace\) <= 64/);
    assert.doesNotMatch(durableStateSchema, /\spayload\s+STRING/);
  });

  it('adds flat-schema tenant RLS helpers and policies', () => {
    assert.match(postgresTenantRls, /arth_request_user_id/);
    assert.match(postgresTenantRls, /arth_is_system_request/);
    assert.match(postgresTenantRls, /arth_tenant_visible/);
    assert.match(postgresTenantRls, /FORCE ROW LEVEL SECURITY/);
    assert.match(postgresTenantRls, /tax_documents/);
    assert.match(postgresTenantRls, /device_tokens/);
    assert.match(postgresTenantRls, /app_user_state_isolation/);
    assert.doesNotMatch(postgresTenantRls, /FOREACH/i);
    assert.doesNotMatch(postgresTenantRls, /DO \$\$/i);
  });
});

describe('AI spend ledger and merchant cache', () => {
  it('creates both tables in both dialects', () => {
    for (const sql of [aiSpendPostgres, aiSpendCockroach]) {
      assert.match(sql, /CREATE TABLE IF NOT EXISTS ai_spend_ledger/);
      assert.match(sql, /CREATE TABLE IF NOT EXISTS merchant_category_cache/);
    }
  });

  it('leaves both tables outside row-level security, on purpose', () => {
    // The cap is one global figure: the runtime has to SUM every user's rows, and
    // an isolation policy would silently turn a single $1.50 cap into $1.50 per
    // user. The cache is shared across users because that sharing IS the saving.
    // Both migrations must explain this, since it reads like an omission.
    for (const sql of [aiSpendPostgres, aiSpendCockroach]) {
      assert.doesNotMatch(sql, /ROW LEVEL SECURITY/);
      assert.doesNotMatch(sql, /CREATE POLICY/);
      // The reasoning must be written down, or the next reader "fixes" it.
      assert.match(sql, /global/i);
    }
  });

  it('keeps no readable merchant text in the shared cache', () => {
    for (const sql of [aiSpendPostgres, aiSpendCockroach]) {
      assert.match(sql, /merchant_hash/);
      assert.doesNotMatch(sql, /merchant_name|merchant_text/);
      // Only a keyed digest of a bounded length is accepted.
      assert.match(sql, /length\(merchant_hash\) BETWEEN 32 AND 128/);
    }
  });

  it('stores money as an integer and forbids negative usage', () => {
    for (const sql of [aiSpendPostgres, aiSpendCockroach]) {
      assert.match(sql, /micro_usd/);
      assert.doesNotMatch(sql, /micro_usd\s+(?:NUMERIC|REAL|FLOAT|DECIMAL|DOUBLE)/i);
      assert.match(sql, /ai_spend_ledger_non_negative/);
    }
  });

  it('restricts table access in the idiom of each dialect', () => {
    assert.match(aiSpendPostgres, /REVOKE ALL ON TABLE ai_spend_ledger FROM PUBLIC/);
    assert.match(aiSpendCockroach, /GRANT SELECT, INSERT ON TABLE ai_spend_ledger TO arth_app_runtime/);
  });
});

describe('offer comparison sessions', () => {
  it('creates both tables in both dialects', () => {
    assert.match(offerComparisonsPostgres, /CREATE TABLE IF NOT EXISTS offer_comparisons/);
    assert.match(
      offerComparisonsPostgres,
      /CREATE TABLE IF NOT EXISTS offer_comparison_offers/,
    );
    assert.match(
      offerComparisonsCockroach,
      /CREATE TABLE IF NOT EXISTS payroll\.offer_comparisons/,
    );
    assert.match(
      offerComparisonsCockroach,
      /CREATE TABLE IF NOT EXISTS payroll\.offer_comparison_offers/,
    );
  });

  it('keeps no readable salary figures in either dialect', () => {
    // A comparison payload holds normalized pay. tax_documents already refuses to
    // keep extracted salary fields readable (storedParseSummary encrypts them),
    // so a plaintext comparison column here would quietly undo that decision.
    assert.match(offerComparisonsPostgres, /state_encrypted\s+JSONB NOT NULL/);
    assert.match(offerComparisonsCockroach, /payload_ciphertext\s+BYTES NOT NULL/);
    assert.match(offerComparisonsCockroach, /payload_nonce\s+BYTES NOT NULL/);
    for (const sql of [offerComparisonsPostgres, offerComparisonsCockroach]) {
      assert.doesNotMatch(sql, /annual_ctc|fixed_pay|variable_pay|take_home/i);
    }
  });

  it('isolates sessions per user, unlike the global spend ledger', () => {
    // Every column here belongs to exactly one candidate, so this table gets the
    // isolation the spend ledger deliberately does without.
    assert.match(offerComparisonsPostgres, /ENABLE ROW LEVEL SECURITY/);
    assert.match(
      offerComparisonsPostgres,
      /CREATE POLICY tenant_isolation ON offer_comparisons/,
    );
    assert.match(
      offerComparisonsPostgres,
      /CREATE POLICY tenant_isolation ON offer_comparison_offers/,
    );
    assert.match(
      offerComparisonsPostgres,
      /REVOKE ALL ON TABLE offer_comparisons FROM PUBLIC/,
    );
    assert.match(
      offerComparisonsCockroach,
      /GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE payroll\.offer_comparisons TO arth_app_runtime/,
    );
  });

  it('cascades a session away with the document it compared', () => {
    // A comparison that outlives one of its own offer letters would keep
    // answering with a figure the user believes they deleted.
    assert.match(
      offerComparisonsPostgres,
      /document_id\s+UUID NOT NULL REFERENCES tax_documents\(id\) ON DELETE CASCADE/,
    );
    assert.match(
      offerComparisonsCockroach,
      /REFERENCES vault\.documents\(user_id, id\) ON DELETE CASCADE/,
    );
  });

  it('bounds the session lifecycle and the offer count', () => {
    for (const sql of [offerComparisonsPostgres, offerComparisonsCockroach]) {
      assert.match(sql, /status IN \('questions_pending', 'answered', 'advised'\)/);
      assert.match(sql, /position BETWEEN 0 AND 9/);
    }
  });
});
