import 'dotenv/config';

import { createHash, randomUUID } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

function requireDatabaseUrl(): string {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error('DATABASE_URL is required to run migrations');
  }
  return url;
}

const databaseUrl: string = requireDatabaseUrl();

const dialect = process.env.DB_DIALECT === 'cockroach' ? 'cockroach' : 'postgres';
const sqlDirectory = dialect === 'cockroach'
  ? fileURLToPath(new URL('../../sql/cockroach/', import.meta.url))
  : fileURLToPath(new URL('../../sql/', import.meta.url));
const migrationTable = dialect === 'cockroach'
  ? 'ops.schema_migrations'
  : 'schema_migrations';
const lockTable = dialect === 'cockroach'
  ? 'ops.migration_lock'
  : 'migration_lock';

const transientDbErrorCodes = new Set([
  'ECONNREFUSED',
  '40001',
  'ECONNRESET',
  'ETIMEDOUT',
  'ENOTFOUND',
  'EAI_AGAIN',
  '57P01',
  '57P02',
  '57P03',
  '08000',
  '08003',
  '08006',
  '53300',
]);

function isTransientDbError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;

  const code = (error as { code?: unknown }).code;
  if (typeof code === 'string' && transientDbErrorCodes.has(code)) return true;

  const nested = error as { errors?: unknown; aggregateErrors?: unknown };
  const children = Array.isArray(nested.errors)
    ? nested.errors
    : Array.isArray(nested.aggregateErrors)
      ? nested.aggregateErrors
      : [];
  return children.some(isTransientDbError);
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function connectWithRetry(): Promise<pg.Client> {
  const delays = [1_000, 2_000, 4_000, 8_000, 10_000, 10_000];
  let lastError: unknown;

  for (let attempt = 0; attempt <= delays.length; attempt += 1) {
    const client = new pg.Client({
      connectionString: databaseUrl,
      connectionTimeoutMillis: 10_000,
    });
    try {
      await client.connect();
      return client;
    } catch (error) {
      lastError = error;
      await client.end().catch(() => undefined);
      if (!isTransientDbError(error) || attempt === delays.length) throw error;
      const waitMs = delays[attempt];
      console.warn(`[migration] database unavailable; retrying in ${waitMs}ms`);
      await delay(waitMs);
    }
  }

  throw lastError;
}

function isCockroachConnectionString(connection: string): boolean {
  try {
    const url = new URL(connection);
    if (url.port === '26257') return true;
    const host = url.hostname.toLowerCase();
    return host.includes('cockroachlabs.cloud') || host.includes('cockroach');
  } catch {
    return connection.toLowerCase().includes('cockroach');
  }
}

function isPostgresOnlyMigration(filename: string): boolean {
  return filename.includes('.postgres-only.');
}

async function migrate() {
  const client = await connectWithRetry();
  const holder = randomUUID();
  const runningFlatMigrationsOnCockroach = dialect === 'postgres'
    && isCockroachConnectionString(databaseUrl);
  if (runningFlatMigrationsOnCockroach) {
    console.warn(
      '[migration] DB_DIALECT=postgres with a CockroachDB URL: applying flat sql/ migrations',
    );
  }
  try {
    if (dialect === 'cockroach') {
      await client.query('create schema if not exists ops');
    }
    await client.query(`
      create table if not exists ${migrationTable} (
        filename text primary key,
        checksum text not null,
        applied_at timestamptz not null default now()
      )
    `);
    await client.query(`
      create table if not exists ${lockTable} (
        lock_name text primary key,
        holder uuid not null,
        expires_at timestamptz not null
      )
    `);
    const locked = await client.query(
      `insert into ${lockTable} (lock_name, holder, expires_at)
       values ('schema', $1, $2)
       on conflict (lock_name) do update
       set holder = excluded.holder, expires_at = excluded.expires_at
       where ${lockTable}.expires_at < now()
          or ${lockTable}.holder = excluded.holder
       returning holder`,
      [holder, new Date(Date.now() + 15 * 60 * 1_000)],
    );
    if (!locked.rowCount) {
      throw new Error('Another schema migration is running');
    }

    const filenames = (await readdir(sqlDirectory))
      .filter((filename) => filename.endsWith('.sql'))
      .sort((left, right) => left.localeCompare(right));

    for (const filename of filenames) {
      if (runningFlatMigrationsOnCockroach && isPostgresOnlyMigration(filename)) {
        console.warn(`[migration] skipped postgres-only migration on CockroachDB: ${filename}`);
        continue;
      }
      const sql = await readFile(join(sqlDirectory, filename), 'utf8');
      const checksum = createHash('sha256').update(sql).digest('hex');
      const existing = await client.query(
        `select checksum from ${migrationTable} where filename = $1`,
        [filename],
      );
      if (existing.rowCount) {
        if (existing.rows[0].checksum !== checksum) {
          throw new Error(`Applied migration changed: ${filename}`);
        }
        continue;
      }

      await client.query('begin');
      try {
        await client.query(sql);
        await client.query(
          `insert into ${migrationTable} (filename, checksum) values ($1, $2)`,
          [filename, checksum],
        );
        await client.query('commit');
        console.log(`[migration] applied ${filename}`);
      } catch (error) {
        await client.query('rollback');
        throw error;
      }
    }
  } finally {
    await client.query(
      `delete from ${lockTable} where lock_name = 'schema' and holder = $1`,
      [holder],
    ).catch(() => undefined);
    await client.end();
  }
}

migrate().catch((error) => {
  console.error('[migration] failed', error);
  process.exitCode = 1;
});
