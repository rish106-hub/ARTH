import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { describe, it } from 'node:test';

const schema = await readFile(
  new URL('../sql/cockroach/001_secure_schema.sql', import.meta.url),
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
});
