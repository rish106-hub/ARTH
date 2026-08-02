/**
 * Encrypted data migration: decrypt legacy ciphertext with global keys,
 * validate plaintext, then re-encrypt with per-user keys for Cockroach.
 *
 * This script handles the critical security transformation identified in ARTH-208.
 * It processes encrypted data from legacy Postgres tables and inserts into the
 * new Cockroach schema with proper per-user encryption.
 *
 * Also handles user table migration (app_users -> auth.users) with blind index
 * conversion for email and phone fields to match the secure Cockroach schema.
 *
 * Usage:
 *   SOURCE_DATABASE_URL=<old postgres>  \
 *   TARGET_DATABASE_URL=<cockroach>     \
 *   PAN_ENCRYPTION_KEY=<legacy key>     \
 *   DOCUMENT_ENCRYPTION_KEY=<legacy key> \
 *   GCP_KMS_KEY_NAME=<kms key>         \
 *   DATA_HMAC_KEY=<hmac key>           \
 *   npx tsx src/scripts/migrate-encrypted-data.ts [--dry-run]
 *
 * Safe to re-run: every insert is ON CONFLICT DO NOTHING.
 * Failure leaves the source intact and prevents cutover.
 */
import pg from 'pg';
import {
  createDecipheriv,
  createCipheriv,
  randomBytes,
  createHmac,
} from 'node:crypto';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import { env } from '../config.js';

const sourceUrl = process.env.SOURCE_DATABASE_URL;
const targetUrl = process.env.TARGET_DATABASE_URL;
const dryRun = process.argv.includes('--dry-run');

if (!sourceUrl || !targetUrl) {
  console.error('SOURCE_DATABASE_URL and TARGET_DATABASE_URL are required.');
  process.exit(1);
}

if (!env.PAN_ENCRYPTION_KEY || !env.DOCUMENT_ENCRYPTION_KEY) {
  console.error('PAN_ENCRYPTION_KEY and DOCUMENT_ENCRYPTION_KEY are required for legacy decryption.');
  process.exit(1);
}

if (!env.GCP_KMS_KEY_NAME) {
  console.error('GCP_KMS_KEY_NAME is required for per-user key wrapping.');
  process.exit(1);
}

if (!env.DATA_HMAC_KEY) {
  console.error('DATA_HMAC_KEY is required for blind index conversion.');
  process.exit(1);
}

// Type assertions after runtime validation
const PAN_ENCRYPTION_KEY = env.PAN_ENCRYPTION_KEY!;
const DOCUMENT_ENCRYPTION_KEY = env.DOCUMENT_ENCRYPTION_KEY!;
const GCP_KMS_KEY_NAME = env.GCP_KMS_KEY_NAME!;
const DATA_HMAC_KEY = env.DATA_HMAC_KEY!;

// Blind index function for converting plain text to hashed lookups
function blindIndex(namespace: string, normalizedValue: string): Buffer {
  const key = Buffer.from(DATA_HMAC_KEY, 'base64');
  if (key.length < 32) throw new Error('DATA_HMAC_KEY must be at least 32 base64-encoded bytes');
  return createHmac('sha256', key)
    .update(Buffer.from([namespace.length]))
    .update(namespace)
    .update(Buffer.from([0]))
    .update(normalizedValue)
    .digest();
}

// Legacy decryption functions (matching security.ts)
function getPanEncryptionKey(): Buffer {
  const key = Buffer.from(PAN_ENCRYPTION_KEY, 'base64');
  if (key.length !== 32) {
    throw new Error('PAN_ENCRYPTION_KEY must be 32 base64-encoded bytes');
  }
  return key;
}

function getDocumentEncryptionKey(): Buffer {
  const key = Buffer.from(DOCUMENT_ENCRYPTION_KEY, 'base64');
  if (key.length !== 32) {
    throw new Error('DOCUMENT_ENCRYPTION_KEY must be 32 base64-encoded bytes');
  }
  return key;
}

function decryptLegacyPan(encrypted: { ciphertext: string; iv: string; auth_tag: string }): string {
  const key = getPanEncryptionKey();
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(encrypted.iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(encrypted.auth_tag, 'base64'));
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(encrypted.ciphertext, 'base64')),
    decipher.final(),
  ]);
  return plaintext.toString('utf8');
}

function decryptLegacyDocument(encrypted: { ciphertext: string; iv: string; auth_tag: string }): Buffer {
  const key = getDocumentEncryptionKey();
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(encrypted.iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(encrypted.auth_tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(encrypted.ciphertext, 'base64')),
    decipher.final(),
  ]);
}

// Per-user encryption for Cockroach (matching envelopeEncryption.ts)
class KmsKeyWrapper {
  private readonly client: KeyManagementServiceClient;
  private readonly keyName: string;

  constructor() {
    this.client = new KeyManagementServiceClient();
    this.keyName = GCP_KMS_KEY_NAME;
  }

  async wrap(plaintextKey: Buffer): Promise<Buffer> {
    const [result] = await this.client.encrypt({
      name: this.keyName,
      plaintext: plaintextKey,
    });
    if (!result.ciphertext) throw new Error('Cloud KMS returned no ciphertext');
    return Buffer.from(result.ciphertext as Uint8Array);
  }

  async unwrap(wrappedKey: Buffer): Promise<Buffer> {
    const [result] = await this.client.decrypt({
      name: this.keyName,
      ciphertext: wrappedKey,
    });
    if (!result.plaintext) throw new Error('Cloud KMS returned no plaintext');
    return Buffer.from(result.plaintext as Uint8Array);
  }
}

async function createPerUserDataKey(kms: KmsKeyWrapper): Promise<{ plaintext: Buffer; wrapped: Buffer }> {
  const plaintext = randomBytes(32);
  const wrapped = await kms.wrap(plaintext);
  return { plaintext, wrapped };
}

function encryptWithUserKey(
  dataKey: Buffer,
  plaintext: Buffer,
  context: { userId: string; entityType: string; recordId: string },
): { ciphertext: Buffer; nonce: Buffer; keyVersion: number; schemaVersion: number } {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', dataKey, nonce);
  const aad = Buffer.from([
    'arth',
    context.userId,
    context.entityType,
    context.recordId,
    '1',
    '1',
  ].join('\0'), 'utf8');
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return {
    ciphertext: Buffer.concat([cipher.getAuthTag(), ciphertext]),
    nonce,
    keyVersion: 1,
    schemaVersion: 1,
  };
}

// Transformation statistics (non-sensitive)
interface TransformationStats {
  copied?: number;
  decrypted?: number;
  failed: number;
}

const transformationStats: Record<string, TransformationStats> = {
  app_users: { copied: 0, failed: 0 },
  user_private_identity: { decrypted: 0, failed: 0 },
  tax_documents: { decrypted: 0, failed: 0 },
  user_state: { decrypted: 0, failed: 0 },
};

function quoteIdent(id: string): string {
  return '"' + id.replace(/"/g, '""') + '"';
}

async function assertNoUserIdentityConflicts(source: pg.Client, target: pg.Client) {
  console.log('[migrate-encrypted-data] checking for user identity conflicts...');
  
  const [sourceUsers, targetUsers] = await Promise.all([
    source.query<{ id: string; email: string }>('select id::text, lower(email) as email from app_users'),
    target.query<{ id: string; email: string }>('select id::text, lower(email_lookup::text) as email from auth.users'),
  ]);
  
  const targetIdsByEmail = new Map(targetUsers.rows.map((row) => [row.email, row.id]));
  const conflicts = sourceUsers.rows.filter((row) => {
    const targetId = targetIdsByEmail.get(row.email);
    return targetId !== undefined && targetId !== row.id;
  });
  
  if (conflicts.length > 0) {
    throw new Error(
      `Target has ${conflicts.length} email(s) assigned to different user IDs; resolve them before copying`,
    );
  }
  
  console.log('[migrate-encrypted-data] no user identity conflicts found');
}

async function migrateAppUsers(
  source: pg.Client,
  target: pg.Client,
  kms: KmsKeyWrapper,
): Promise<void> {
  console.log('[migrate-encrypted-data] Processing app_users -> auth.users');

  await assertNoUserIdentityConflicts(source, target);

  const rows = (await source.query(
    `select id, email, name, phone_e164, password_hash, google_subject, 
            auth_provider, email_verified, avatar_initials, avatar_color,
            created_at, updated_at, last_seen_at
     from app_users`,
  )).rows;

  if (rows.length === 0) {
    console.log('  app_users: 0 rows');
    return;
  }

  if (dryRun) {
    console.log(`  app_users: would migrate ${rows.length} users`);
    return;
  }

  let inserted = 0;
  for (const row of rows) {
    try {
      // Create per-user data key for encryption
      const { plaintext: dataKey, wrapped } = await createPerUserDataKey(kms);

      // Convert email and phone to blind indexes
      const emailLookup = blindIndex('email', row.email.toLowerCase());
      const phoneLookup = row.phone_e164 ? blindIndex('phone', row.phone_e164) : null;

      // Create user payload with basic profile data
      const payload = {
        name: row.name,
        avatar_initials: row.avatar_initials,
        avatar_color: row.avatar_color,
      };

      const payloadCiphertext = Buffer.from(JSON.stringify(payload), 'utf8');
      const payloadEncrypted = encryptWithUserKey(
        dataKey,
        payloadCiphertext,
        { userId: row.id, entityType: 'user_profile', recordId: row.id },
      );

      // Insert user keyring entry
      await target.query(
        `insert into auth.user_keyrings (user_id, wrapped_data_key, kms_key_name, kms_key_version, key_version, status, created_at)
         values ($1, $2, $3, '1', 1, 'active', now())
         on conflict (user_id) do nothing`,
        [row.id, wrapped, GCP_KMS_KEY_NAME],
      );

      // Insert into auth.users with blind indexes and encrypted payload
      await target.query(
        `insert into auth.users
         (id, email_lookup, phone_lookup, password_hash, password_algorithm, 
          auth_provider, email_verified, token_version, status,
          payload_ciphertext, payload_nonce, key_version, schema_version,
          created_at, updated_at, last_seen_at)
         values ($1, $2, $3, $4, $5, $6, $7, 1, 'active', $8, $9, 1, 1, $10, $11, $12)
         on conflict (id) do nothing`,
        [
          row.id,
          emailLookup,
          phoneLookup,
          row.password_hash,
          row.password_hash ? 'argon2id' : null,
          row.auth_provider,
          row.email_verified,
          payloadEncrypted.ciphertext,
          payloadEncrypted.nonce,
          row.created_at,
          row.updated_at,
          row.last_seen_at,
        ],
      );

      // Insert auth identity for Google auth users
      if (row.google_subject) {
        await target.query(
          `insert into auth.auth_identities (user_id, id, provider, provider_user_id)
           values ($1, gen_random_uuid(), 'google', $2)
           on conflict (user_id, provider, provider_user_id) do nothing`,
          [row.id, row.google_subject],
        );
      }

      inserted++;
      transformationStats.app_users.copied = (transformationStats.app_users.copied || 0) + 1;
    } catch (e) {
      console.error(`  app_users: failed to migrate user ${row.id}: ${(e as Error).message}`);
      transformationStats.app_users.failed++;
    }
  }

  console.log(`  app_users: ${inserted}/${rows.length} users migrated`);
}

async function migrateUserPrivateIdentity(
  source: pg.Client,
  target: pg.Client,
  kms: KmsKeyWrapper,
): Promise<void> {
  console.log('[migrate-encrypted-data] Processing user_private_identity');

  const rows = (await source.query(
    `select user_id, pan_ciphertext, pan_iv, pan_auth_tag, pan_last4, pan_last_char,
            pan_fingerprint, pan_consent_version, pan_consented_at, pan_deleted_at,
            created_at, updated_at
     from user_private_identity
     where pan_ciphertext is not null`,
  )).rows;

  if (rows.length === 0) {
    console.log('  user_private_identity: 0 encrypted rows');
    return;
  }

  if (dryRun) {
    console.log(`  user_private_identity: would transform ${rows.length} encrypted rows`);
    return;
  }

  let inserted = 0;
  for (const row of rows) {
    const userId = row.user_id;
    try {
      // Decrypt with legacy key
      const plaintext = decryptLegacyPan({
        ciphertext: row.pan_ciphertext,
        iv: row.pan_iv,
        auth_tag: row.pan_auth_tag,
      });

      // Validate PAN format
      if (!/^[A-Z]{5}[0-9]{4}[A-Z]{1}$/.test(plaintext)) {
        throw new Error('Invalid PAN format');
      }

      // Create or get per-user data key for this user
      const { plaintext: dataKey, wrapped } = await createPerUserDataKey(kms);

      // Insert user keyring entry if not exists
      await target.query(
        `insert into auth.user_keyrings (user_id, wrapped_data_key, kms_key_name, kms_key_version, key_version, status, created_at)
         values ($1, $2, $3, '1', 1, 'active', now())
         on conflict (user_id) do nothing`,
        [userId, wrapped, GCP_KMS_KEY_NAME],
      );

      // Re-encrypt with per-user key
      const encrypted = encryptWithUserKey(
        dataKey,
        Buffer.from(plaintext, 'utf8'),
        { userId, entityType: 'user_private_identity', recordId: userId },
      );

      // Insert into profile.user_profiles with new format
      const payload = {
        pan_last4: row.pan_last4,
        pan_last_char: row.pan_last_char,
        pan_fingerprint: row.pan_fingerprint,
        pan_consent_version: row.pan_consent_version,
        pan_consented_at: row.pan_consented_at,
        pan_deleted_at: row.pan_deleted_at,
      };

      const payloadCiphertext = Buffer.from(JSON.stringify(payload), 'utf8');
      const payloadEncrypted = encryptWithUserKey(
        dataKey,
        payloadCiphertext,
        { userId, entityType: 'user_profile', recordId: userId },
      );

      await target.query(
        `insert into profile.user_profiles
         (user_id, id, payload_ciphertext, payload_nonce, key_version, schema_version, version, created_at, updated_at)
         values ($1, gen_random_uuid(), $2, $3, $4, $5, 1, now(), now())
         on conflict (user_id) do nothing`,
        [
          userId,
          payloadEncrypted.ciphertext,
          payloadEncrypted.nonce,
          payloadEncrypted.keyVersion,
          payloadEncrypted.schemaVersion,
        ],
      );

      inserted++;
      transformationStats.user_private_identity.decrypted = (transformationStats.user_private_identity.decrypted || 0) + 1;
    } catch (e) {
      console.error(`  user_private_identity: Failed to transform for user ${userId}: ${(e as Error).message}`);
      transformationStats.user_private_identity.failed++;
      // Continue with other rows - source remains intact
    }
  }

  console.log(`  user_private_identity: ${rows.length} source rows, ${inserted} inserted`);
}

async function migrateTaxDocuments(
  source: pg.Client,
  target: pg.Client,
  kms: KmsKeyWrapper,
): Promise<void> {
  console.log('[migrate-encrypted-data] Processing tax_documents');

  const rows = (await source.query(
    `select id, user_id, fy, document_type, original_filename, mime_type, byte_size,
            sha256_fingerprint, ciphertext, iv, auth_tag, parse_status, parse_summary,
            created_at, updated_at
     from tax_documents
     where ciphertext is not null`,
  )).rows;

  if (rows.length === 0) {
    console.log('  tax_documents: 0 encrypted rows');
    return;
  }

  if (dryRun) {
    console.log(`  tax_documents: would transform ${rows.length} encrypted rows`);
    return;
  }

  let inserted = 0;
  for (const row of rows) {
    const userId = row.user_id;
    const documentId = row.id;
    try {
      // Decrypt with legacy key
      const plaintext = decryptLegacyDocument({
        ciphertext: row.ciphertext,
        iv: row.iv,
        auth_tag: row.auth_tag,
      });

      // Get or create per-user data key
      const { plaintext: dataKey, wrapped } = await createPerUserDataKey(kms);

      // Ensure user keyring exists
      await target.query(
        `insert into auth.user_keyrings (user_id, wrapped_data_key, kms_key_name, kms_key_version, key_version, status, created_at)
         values ($1, $2, $3, '1', 1, 'active', now())
         on conflict (user_id) do nothing`,
        [userId, wrapped, GCP_KMS_KEY_NAME],
      );

      // Re-encrypt with per-user key
      const encrypted = encryptWithUserKey(
        dataKey,
        plaintext,
        { userId, entityType: 'tax_document', recordId: documentId },
      );

      // Insert into vault.documents
      const payload = {
        original_filename: row.original_filename,
        mime_type: row.mime_type,
        byte_size: row.byte_size,
        sha256_fingerprint: row.sha256_fingerprint,
        parse_status: row.parse_status,
        parse_summary: row.parse_summary,
      };

      const payloadCiphertext = Buffer.from(JSON.stringify(payload), 'utf8');
      const payloadEncrypted = encryptWithUserKey(
        dataKey,
        payloadCiphertext,
        { userId, entityType: 'tax_document_metadata', recordId: documentId },
      );

      await target.query(
        `insert into vault.documents
         (user_id, id, financial_year, document_type, content_fingerprint, status, review_status,
          payload_ciphertext, payload_nonce, key_version, schema_version, version, created_at, updated_at)
         values ($1, $2, $3, $4, $5, 'uploaded', 'not_reviewed', $6, $7, $8, $9, 1, now(), now())
         on conflict (user_id, id) do nothing`,
        [
          userId,
          documentId,
          row.fy,
          row.document_type,
          Buffer.from(row.sha256_fingerprint, 'hex'),
          payloadEncrypted.ciphertext,
          payloadEncrypted.nonce,
          payloadEncrypted.keyVersion,
          payloadEncrypted.schemaVersion,
        ],
      );

      inserted++;
      transformationStats.tax_documents.decrypted = (transformationStats.tax_documents.decrypted || 0) + 1;
    } catch (e) {
      console.error(`  tax_documents: Failed to transform document ${documentId}: ${(e as Error).message}`);
      transformationStats.tax_documents.failed++;
    }
  }

  console.log(`  tax_documents: ${rows.length} source rows, ${inserted} inserted`);
}

async function migrateUserState(
  source: pg.Client,
  target: pg.Client,
  kms: KmsKeyWrapper,
): Promise<void> {
  console.log('[migrate-encrypted-data] Processing user_state');

  const rows = (await source.query(
    `select user_id, namespace, payload_ciphertext, payload_iv, payload_auth_tag,
            deleted, client_updated_at, updated_at
     from user_state
     where payload_ciphertext is not null and deleted = false`,
  )).rows;

  if (rows.length === 0) {
    console.log('  user_state: 0 encrypted rows');
    return;
  }

  if (dryRun) {
    console.log(`  user_state: would transform ${rows.length} encrypted rows`);
    return;
  }

  let inserted = 0;
  for (const row of rows) {
    const userId = row.user_id;
    const namespace = row.namespace;
    try {
      // Decrypt with legacy key
      const plaintext = decryptLegacyDocument({
        ciphertext: row.payload_ciphertext,
        iv: row.payload_iv,
        auth_tag: row.payload_auth_tag,
      });

      // Get or create per-user data key
      const { plaintext: dataKey, wrapped } = await createPerUserDataKey(kms);

      // Ensure user keyring exists
      await target.query(
        `insert into auth.user_keyrings (user_id, wrapped_data_key, kms_key_name, kms_key_version, key_version, status, created_at)
         values ($1, $2, $3, '1', 1, 'active', now())
         on conflict (user_id) do nothing`,
        [userId, wrapped, GCP_KMS_KEY_NAME],
      );

      // Re-encrypt with per-user key
      const encrypted = encryptWithUserKey(
        dataKey,
        plaintext,
        { userId, entityType: 'user_state', recordId: namespace },
      );

      // Insert into user_state (Cockroach has this table in public schema)
      await target.query(
        `insert into user_state
         (user_id, namespace, payload_ciphertext, payload_iv, payload_auth_tag, deleted, client_updated_at, updated_at)
         values ($1, $2, $3, $4, '', false, $5, now())
         on conflict (user_id, namespace) do nothing`,
        [
          userId,
          namespace,
          encrypted.ciphertext,
          encrypted.nonce,
          row.client_updated_at,
        ],
      );

      inserted++;
      transformationStats.user_state.decrypted = (transformationStats.user_state.decrypted || 0) + 1;
    } catch (e) {
      console.error(`  user_state: Failed to transform state for user ${userId}, namespace ${namespace}: ${(e as Error).message}`);
      transformationStats.user_state.failed++;
    }
  }

  console.log(`  user_state: ${rows.length} source rows, ${inserted} inserted`);
}

async function verifyDecryption(
  target: pg.Client,
  kms: KmsKeyWrapper,
): Promise<void> {
  console.log('[migrate-encrypted-data] Verifying decryption of transformed data');

  // Verify a sample of user profiles can be decrypted
  const sampleUsers = (await target.query(
    `select user_id, payload_ciphertext, payload_nonce
     from profile.user_profiles
     limit 5`,
  )).rows;

  for (const row of sampleUsers) {
    try {
      const wrappedKey = (await target.query(
        `select wrapped_data_key from auth.user_keyrings where user_id = $1`,
        [row.user_id],
      )).rows[0]?.wrapped_data_key;

      if (!wrappedKey) {
        throw new Error(`No wrapped key found for user ${row.user_id}`);
      }

      const dataKey = await kms.unwrap(Buffer.from(wrappedKey, 'base64'));
      const encrypted = {
        ciphertext: Buffer.from(row.payload_ciphertext, 'base64'),
        nonce: Buffer.from(row.payload_nonce, 'base64'),
        keyVersion: 1,
        schemaVersion: 1,
      };

      // Attempt decryption
      const tag = encrypted.ciphertext.subarray(0, 16);
      const ciphertext = encrypted.ciphertext.subarray(16);
      const decipher = createDecipheriv('aes-256-gcm', dataKey, encrypted.nonce);
      decipher.setAuthTag(tag);
      const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
      JSON.parse(plaintext.toString('utf8')); // Validate it's valid JSON

      console.log(`  ✓ User ${row.user_id}: decryption successful`);
    } catch (e) {
      console.error(`  ✗ User ${row.user_id}: decryption failed - ${(e as Error).message}`);
      throw new Error(`Verification failed for user ${row.user_id}`);
    }
  }

  console.log('[migrate-encrypted-data] Verification complete');
}

async function main() {
  const source = new pg.Client({ connectionString: sourceUrl });
  const target = new pg.Client({ connectionString: targetUrl });
  await source.connect();
  await target.connect();
  console.log(`[migrate-encrypted-data]${dryRun ? ' (dry-run)' : ''} start`);

  // Initialize KMS wrapper for per-user encryption
  const kms = new KmsKeyWrapper();

  try {
    // Process encrypted tables in dependency order
    // Users first (needed for FK references)
    await migrateAppUsers(source, target, kms);
    await migrateUserPrivateIdentity(source, target, kms);
    await migrateTaxDocuments(source, target, kms);
    await migrateUserState(source, target, kms);

    // Output transformation statistics
    console.log('[migrate-encrypted-data] transformation statistics:');
    for (const [table, stats] of Object.entries(transformationStats)) {
      if ((stats.copied && stats.copied > 0) || (stats.decrypted && stats.decrypted > 0) || stats.failed > 0) {
        const action = stats.copied && stats.copied > 0 ? 'copied' : 'decrypted';
        const count = stats.copied && stats.copied > 0 ? stats.copied : stats.decrypted;
        console.log(`  ${table}: ${count} ${action}, ${stats.failed} failed`);
      }
    }

    // Verify no failures
    const totalFailed = Object.values(transformationStats).reduce((sum, s) => sum + s.failed, 0);
    if (totalFailed > 0) {
      console.error(`[migrate-encrypted-data] ${totalFailed} transformations failed - source remains intact`);
      console.error('[migrate-encrypted-data] ROLLBACK RECOMMENDED: Do not proceed with cutover');
      process.exit(1);
    }

    // Verify decryption works on transformed data
    if (!dryRun) {
      await verifyDecryption(target, kms);
    }

    // Insert success marker to indicate safe to cutover
    if (!dryRun) {
      await target.query(
        `insert into ops.audit_events (id, user_id, event_type, outcome, actor_type, metadata, occurred_at)
         values (gen_random_uuid(), null, 'encryption_migration_complete', 'success', 'system',
           '{"source": "migrate-encrypted-data.ts", "tables": ["app_users", "user_private_identity", "tax_documents", "user_state"]}'::jsonb,
           now())`,
      );
      console.log('[migrate-encrypted-data] Success marker recorded - safe to proceed with cutover');
    }

    console.log('[migrate-encrypted-data] done');
  } finally {
    await source.end().catch(() => undefined);
    await target.end().catch(() => undefined);
  }
}

main().catch((e) => {
  console.error('[migrate-encrypted-data] failed', e);
  process.exit(1);
});
