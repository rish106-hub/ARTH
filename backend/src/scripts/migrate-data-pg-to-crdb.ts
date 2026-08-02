/**
 * One-shot data migration: copy non-encrypted user data from the old flat
 * Postgres DB into the Cockroach multi-tenant schema.
 *
 * Encrypted data transformation is handled by migrate-encrypted-data.ts
 * to properly handle the per-user encryption model.
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

// FK-ordered: parents before children. Maps Postgres tables to Cockroach schemas.
// Only includes tables that can be directly copied without encryption transformation.
const TABLE_MAPPINGS: Array<{
  source: string;
  target: string;
  conflict: string;
}> = [
  { source: 'app_users', target: 'auth.users', conflict: 'id' },
  { source: 'security_tombstones', target: 'privacy.security_tombstones', conflict: 'deletion_id' },
  { source: 'employer_catalog', target: 'reference.employers', conflict: 'normalized_name' },
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

    for (const { source: sourceTable, target: targetTable, conflict } of TABLE_MAPPINGS) {
      // Intersect columns so the copy is resilient to minor schema drift.
      const [srcCols, tgtCols] = await Promise.all([
        columnsOf(source, sourceTable),
        columnsOf(target, targetTable),
      ]);
      const cols = srcCols.filter((c) => tgtCols.includes(c));
      if (cols.length === 0) {
        console.log(`  ${sourceTable} -> ${targetTable}: skipped (no shared columns / table missing)`);
        continue;
      }

      const rows = (await source.query(
        `select ${cols.map(quoteIdent).join(', ')} from ${quoteIdent(sourceTable)}`,
      )).rows;

      if (rows.length === 0) {
        console.log(`  ${sourceTable} -> ${targetTable}: 0 rows`);
        continue;
      }
      if (dryRun) {
        console.log(`  ${sourceTable} -> ${targetTable}: would copy ${rows.length} rows`);
        continue;
      }

      const colList = cols.map(quoteIdent).join(', ');
      let inserted = 0;
      // Row-by-row keeps it simple and lets ON CONFLICT dedupe on re-runs.
      for (const row of rows) {
        const values = cols.map((c) => row[c]);
        const params = cols.map((_, i) => `$${i + 1}`).join(', ');
        const res = await target.query(
          `insert into ${quoteIdent(targetTable)} (${colList})
           values (${params})
           on conflict (${conflict}) do nothing`,
          values,
        );
        inserted += res.rowCount ?? 0;
      }
      console.log(`  ${sourceTable} -> ${targetTable}: ${rows.length} source rows, ${inserted} inserted`);
    }

    // Verify counts match (source <= target after copy).
    console.log('[migrate-data] verification:');
    for (const { source: sourceTable, target: targetTable } of TABLE_MAPPINGS) {
      try {
        const [s, t] = await Promise.all([
          source.query(`select count(*)::int as n from ${quoteIdent(sourceTable)}`),
          target.query(`select count(*)::int as n from ${quoteIdent(targetTable)}`),
        ]);
        const sn = s.rows[0].n as number;
        const tn = t.rows[0].n as number;
        const ok = tn >= sn ? 'OK' : 'MISMATCH';
        console.log(`  ${sourceTable} -> ${targetTable}: source=${sn} target=${tn} ${ok}`);
      } catch (e) {
        console.log(`  ${sourceTable} -> ${targetTable}: count failed (${(e as Error).message})`);
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
