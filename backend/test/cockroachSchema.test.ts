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
const routes = await readFile(
  new URL('../src/routes.ts', import.meta.url),
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
    assert.match(routes, /set local application_name = 'arth\.\$\{safeUserId\}'/);
    assert.match(routes, /runUserStateTransaction/);
    assert.doesNotMatch(durableStateSchema, /\spayload\s+STRING/);
  });
});
