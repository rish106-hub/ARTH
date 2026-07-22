import 'dotenv/config';

import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is required to run migrations');
}

const sqlDirectory = fileURLToPath(new URL('../../sql/', import.meta.url));

const transientDbErrorCodes = new Set([
  'ECONNREFUSED',
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
      connectionString,
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

async function migrate() {
  const client = await connectWithRetry();
  await client.query("select pg_advisory_lock(hashtext('arth_schema_migrations'))");
  try {
    await client.query(`
      create table if not exists schema_migrations (
        filename text primary key,
        checksum text not null,
        applied_at timestamptz not null default now()
      )
    `);

    const filenames = (await readdir(sqlDirectory))
      .filter((filename) => filename.endsWith('.sql'))
      .sort((left, right) => left.localeCompare(right));

    for (const filename of filenames) {
      const sql = await readFile(new URL(`../../sql/${filename}`, import.meta.url), 'utf8');
      const checksum = createHash('sha256').update(sql).digest('hex');
      const existing = await client.query(
        'select checksum from schema_migrations where filename = $1',
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
          'insert into schema_migrations (filename, checksum) values ($1, $2)',
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
    await client.query("select pg_advisory_unlock(hashtext('arth_schema_migrations'))");
    await client.end();
  }
}

migrate().catch((error) => {
  console.error('[migration] failed', error);
  process.exitCode = 1;
});
