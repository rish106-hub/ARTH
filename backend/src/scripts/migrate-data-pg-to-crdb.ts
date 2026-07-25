/**
 * One-shot data migration: copy user data from the old flat Postgres DB into
 * the Cockroach flat tables (already created by the SQL migrations).
 *
 * Usage:
 *   SOURCE_DATABASE_URL=<old postgres>  \
 *   TARGET_DATABASE_URL=<cockroach>     \
 *   npx tsx src/scripts/migrate-data-pg-to-crdb.ts [--dry-run]
 *
 * Safe to re-run: every insert is ON CONFLICT DO NOTHING keyed on the table's
 * primary key. Order respects foreign keys (app_users first). Run this BEFORE
 * flipping the app's DATABASE_URL to Cockroach.
 */
import pg from 'pg';

const sourceUrl = process.env.SOURCE_DATABASE_URL;
const targetUrl = process.env.TARGET_DATABASE_URL;
const dryRun = process.argv.includes('--dry-run');

if (!sourceUrl || !targetUrl) {
  console.error('SOURCE_DATABASE_URL and TARGET_DATABASE_URL are required.');
  process.exit(1);
}

// FK-ordered: parents before children. Each entry lists the columns to copy and
// the primary-key columns used for the idempotent ON CONFLICT clause.
const TABLES: Array<{ name: string; conflict: string }> = [
  { name: 'app_users', conflict: 'id' },
  { name: 'user_private_identity', conflict: 'user_id' },
  { name: 'auth_refresh_sessions', conflict: 'id' },
  { name: 'tax_profiles', conflict: 'user_id, fy' },
  { name: 'tax_results', conflict: 'user_id, fy' },
  { name: 'done_gaps', conflict: 'user_id, fy, gap_id' },
  { name: 'tax_documents', conflict: 'id' },
  { name: 'document_events', conflict: 'id' },
  { name: 'employer_catalog', conflict: 'normalized_name' },
  { name: 'money_goals', conflict: 'id' },
  { name: 'spend_maps', conflict: 'user_id' },
  { name: 'user_events', conflict: 'id' },
  { name: 'security_tombstones', conflict: 'deletion_id' },
];

function quoteIdent(id: string): string {
  return '"' + id.replace(/"/g, '""') + '"';
}

async function columnsOf(client: pg.Client, table: string): Promise<string[]> {
  const r = await client.query(
    `select column_name from information_schema.columns
     where table_schema = 'public' and table_name = $1
     order by ordinal_position`,
    [table],
  );
  return r.rows.map((row) => row.column_name as string);
}

async function assertNoUserIdentityConflicts(source: pg.Client, target: pg.Client) {
  const [sourceUsers, targetUsers] = await Promise.all([
    source.query<{ id: string; email: string }>('select id::text, lower(email) as email from app_users'),
    target.query<{ id: string; email: string }>('select id::text, lower(email) as email from app_users'),
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
}

async function main() {
  const source = new pg.Client({ connectionString: sourceUrl });
  const target = new pg.Client({ connectionString: targetUrl });
  await source.connect();
  await target.connect();
  console.log(`[migrate-data]${dryRun ? ' (dry-run)' : ''} start`);

  try {
    await assertNoUserIdentityConflicts(source, target);

    for (const { name, conflict } of TABLES) {
      // Intersect columns so the copy is resilient to minor schema drift.
      const [srcCols, tgtCols] = await Promise.all([
        columnsOf(source, name),
        columnsOf(target, name),
      ]);
      const cols = srcCols.filter((c) => tgtCols.includes(c));
      if (cols.length === 0) {
        console.log(`  ${name}: skipped (no shared columns / table missing)`);
        continue;
      }

      const rows = (await source.query(
        `select ${cols.map(quoteIdent).join(', ')} from ${quoteIdent(name)}`,
      )).rows;

      if (rows.length === 0) {
        console.log(`  ${name}: 0 rows`);
        continue;
      }
      if (dryRun) {
        console.log(`  ${name}: would copy ${rows.length} rows`);
        continue;
      }

      const colList = cols.map(quoteIdent).join(', ');
      let inserted = 0;
      // Row-by-row keeps it simple and lets ON CONFLICT dedupe on re-runs.
      for (const row of rows) {
        const values = cols.map((c) => row[c]);
        const params = cols.map((_, i) => `$${i + 1}`).join(', ');
        const res = await target.query(
          `insert into ${quoteIdent(name)} (${colList})
           values (${params})
           on conflict (${conflict}) do nothing`,
          values,
        );
        inserted += res.rowCount ?? 0;
      }
      console.log(`  ${name}: ${rows.length} source rows, ${inserted} inserted`);
    }

    // Verify counts match (source <= target after copy).
    console.log('[migrate-data] verification:');
    for (const { name } of TABLES) {
      try {
        const [s, t] = await Promise.all([
          source.query(`select count(*)::int as n from ${quoteIdent(name)}`),
          target.query(`select count(*)::int as n from ${quoteIdent(name)}`),
        ]);
        const sn = s.rows[0].n as number;
        const tn = t.rows[0].n as number;
        const ok = tn >= sn ? 'OK' : 'MISMATCH';
        console.log(`  ${name}: source=${sn} target=${tn} ${ok}`);
      } catch (e) {
        console.log(`  ${name}: count failed (${(e as Error).message})`);
      }
    }
    console.log('[migrate-data] done');
  } finally {
    await source.end().catch(() => undefined);
    await target.end().catch(() => undefined);
  }
}

main().catch((e) => {
  console.error('[migrate-data] failed', e);
  process.exit(1);
});
