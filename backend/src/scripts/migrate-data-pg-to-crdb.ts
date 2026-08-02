/**
 * One-shot data migration: copy non-encrypted user data from the old flat
 * Postgres DB into the Cockroach multi-tenant schema.
 *
 * User table migration (app_users -> auth.users) is handled by 
 * migrate-encrypted-data.ts to properly handle the per-user encryption model
 * and blind index conversion (email -> email_lookup, phone_e164 -> phone_lookup).
 *
 * Usage:
 *   SOURCE_DATABASE_URL=<old postgres>  \
 *   TARGET_DATABASE_URL=<cockroach>     \
 *   npx tsx src/scripts/migrate-data-pg-to-crdb.ts [--dry-run]
 *
 * Safe to re-run: every insert is ON CONFLICT DO NOTHING keyed on the table's
 * primary key. Order respects foreign keys. Run this BEFORE
 * flipping the app's DATABASE_URL to Cockroach.
 */
import pg from 'pg';

// Minimal shape both the real pg.Client and test fixtures satisfy.
export interface QueryableClient {
  query(sql: string, params?: unknown[]): Promise<{ rows: any[]; rowCount?: number | null }>;
}

// FK-ordered: parents before children. Maps Postgres tables to Cockroach schemas.
// Only includes tables that can be directly copied without encryption transformation.
// Encrypted data transformation is handled by migrate-encrypted-data.ts
export const TABLE_MAPPINGS: Array<{
  source: string;
  target: string;
  conflict: string;
  required: boolean; // Fail migration if table is missing
}> = [
  // Auth domain (parent tables first)
  // Note: app_users -> auth.users is handled by migrate-encrypted-data.ts due to encryption requirements
  { source: 'auth_refresh_sessions', target: 'auth.auth_sessions', conflict: 'id', required: true },
  
  // Profile domain (user data - plain fields only, encrypted payload handled separately)
  { source: 'tax_profiles', target: 'profile.user_profiles', conflict: 'user_id', required: true },
  
  // Tax domain
  { source: 'tax_results', target: 'tax.tax_computations', conflict: 'user_id', required: true },
  { source: 'done_gaps', target: 'tax.readiness_items', conflict: 'user_id', required: true },
  
  // Operations domain
  { source: 'user_events', target: 'ops.audit_events', conflict: 'id', required: false },
  
  // Vault domain (documents - encrypted content handled separately)
  { source: 'tax_documents', target: 'vault.documents', conflict: 'id', required: true },
  { source: 'document_events', target: 'vault.document_events', conflict: 'id', required: true },
  
  // Goals domain
  { source: 'money_goals', target: 'goals.goals', conflict: 'id', required: true },
  
  // Reference data
  { source: 'employer_catalog', target: 'reference.employers', conflict: 'normalized_name', required: true },
  
  // Finance domain
  { source: 'spend_maps', target: 'finance.spend_snapshots', conflict: 'user_id', required: true },
  
  // Privacy domain
  { source: 'security_tombstones', target: 'privacy.security_tombstones', conflict: 'deletion_id', required: true },
  
  // User state (kept in public for compatibility)
  { source: 'user_state', target: 'public.user_state', conflict: 'user_id', required: false },
];

function quoteIdent(id: string): string {
  return '"' + id.replace(/"/g, '""') + '"';
}

// Parse schema-qualified table name (e.g., "auth.users" -> {schema: "auth", table: "users"})
export function parseQualifiedTable(qualified: string): { schema: string; table: string } {
  const parts = qualified.split('.');
  if (parts.length === 2) {
    return { schema: parts[0], table: parts[1] };
  }
  // Default to public for unqualified names
  return { schema: 'public', table: parts[0] };
}

// Quotes each segment of a possibly schema-qualified name separately, e.g.
// "auth.auth_sessions" -> "auth"."auth_sessions". Quoting the whole string as
// one identifier (quoteIdent alone) would reference a literal table named
// with a dot in it instead of `auth_sessions` inside schema `auth`.
function quoteQualifiedIdent(qualified: string): string {
  const { schema, table } = parseQualifiedTable(qualified);
  return schema === 'public' && !qualified.includes('.')
    ? quoteIdent(table)
    : `${quoteIdent(schema)}.${quoteIdent(table)}`;
}

export async function columnsOf(client: QueryableClient, qualifiedTable: string): Promise<string[]> {
  const { schema, table } = parseQualifiedTable(qualifiedTable);
  const r = await client.query(
    `select column_name from information_schema.columns
     where table_schema = $1 and table_name = $2
     order by ordinal_position`,
    [schema, table],
  );
  return r.rows.map((row) => row.column_name as string);
}

export async function tableExists(client: QueryableClient, qualifiedTable: string): Promise<boolean> {
  const { schema, table } = parseQualifiedTable(qualifiedTable);
  const r = await client.query(
    `select 1 from information_schema.tables
     where table_schema = $1 and table_name = $2`,
    [schema, table],
  );
  return r.rows.length > 0;
}

/**
 * Runs the full migration (or dry-run) against already-connected clients.
 * Kept separate from the CLI entrypoint so tests can drive it with fixture
 * clients instead of real database connections.
 */
export async function runMigration(
  source: QueryableClient,
  target: QueryableClient,
  dryRun: boolean,
): Promise<{ totalCopied: number; totalSkipped: number }> {
  console.log(`[migrate-data]${dryRun ? ' (dry-run)' : ''} start`);
  console.log('[migrate-data] skipping user identity conflict check (handled by encrypted migration)');

  // Validate all required tables exist before starting migration.
  console.log('[migrate-data] validating table mappings...');
  const validationErrors: string[] = [];
  const mappingReport: Array<{ source: string; target: string; status: string }> = [];

  for (const { source: sourceTable, target: targetTable, required } of TABLE_MAPPINGS) {
    const sourceExists = await tableExists(source, sourceTable);
    const targetExists = await tableExists(target, targetTable);

    if (!sourceExists && required) {
      validationErrors.push(`Required source table ${sourceTable} does not exist`);
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'ERROR: source missing' });
    } else if (!targetExists && required) {
      validationErrors.push(`Required target table ${targetTable} does not exist`);
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'ERROR: target missing' });
    } else if (!sourceExists && !targetExists) {
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'OK: both missing (optional)' });
    } else if (!sourceExists) {
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'OK: source missing (optional)' });
    } else if (!targetExists) {
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'OK: target missing (optional)' });
    } else {
      mappingReport.push({ source: sourceTable, target: targetTable, status: 'OK' });
    }
  }

  if (validationErrors.length > 0) {
    console.error('[migrate-data] validation failed:');
    for (const error of validationErrors) {
      console.error(`  - ${error}`);
    }
    console.error('[migrate-data] mapping report:');
    for (const report of mappingReport) {
      console.error(`  ${report.source} -> ${report.target}: ${report.status}`);
    }
    throw new Error(`Validation failed with ${validationErrors.length} error(s)`);
  }

  console.log('[migrate-data] mapping report:');
  for (const report of mappingReport) {
    console.log(`  ${report.source} -> ${report.target}: ${report.status}`);
  }

  let totalCopied = 0;
  let totalSkipped = 0;

  for (const { source: sourceTable, target: targetTable, conflict, required } of TABLE_MAPPINGS) {
    // Skip if either table doesn't exist (already validated for required tables).
    const sourceExists = await tableExists(source, sourceTable);
    const targetExists = await tableExists(target, targetTable);
    if (!sourceExists || !targetExists) {
      console.log(`  ${sourceTable} -> ${targetTable}: skipped (table missing)`);
      totalSkipped++;
      continue;
    }

    // Intersect columns so the copy is resilient to minor schema drift.
    const [srcCols, tgtCols] = await Promise.all([
      columnsOf(source, sourceTable),
      columnsOf(target, targetTable),
    ]);
    const cols = srcCols.filter((c) => tgtCols.includes(c));

    if (cols.length === 0) {
      // A required table resolving to zero shared columns is a broken mapping,
      // not an optional gap — surfacing it after the fact (via totalCopied===0)
      // would miss it whenever other tables copied rows successfully.
      if (required) {
        throw new Error(
          `Required table ${sourceTable} -> ${targetTable} has no shared columns; mapping is broken`,
        );
      }
      console.log(`  ${sourceTable} -> ${targetTable}: skipped (no shared columns)`);
      totalSkipped++;
      continue;
    }

    const colList = cols.map(quoteIdent).join(', ');

    const rows = (await source.query(
      `select ${colList} from ${quoteIdent(sourceTable)}`,
    )).rows;

    if (rows.length === 0) {
      console.log(`  ${sourceTable} -> ${targetTable}: 0 rows`);
      continue;
    }
    if (dryRun) {
      console.log(`  ${sourceTable} -> ${targetTable}: would copy ${rows.length} rows`);
      totalCopied += rows.length;
      continue;
    }

    let inserted = 0;
    // Row-by-row keeps it simple and lets ON CONFLICT dedupe on re-runs.
    for (const row of rows) {
      const values = cols.map((c) => row[c]);
      const params = cols.map((_, i) => `$${i + 1}`).join(', ');
      const res = await target.query(
        `insert into ${quoteQualifiedIdent(targetTable)} (${colList})
         values (${params})
         on conflict (${conflict}) do nothing`,
        values,
      );
      inserted += res.rowCount ?? 0;
    }
    console.log(`  ${sourceTable} -> ${targetTable}: ${rows.length} source rows, ${inserted} inserted`);
    totalCopied += inserted;
  }

  // Verify counts match (source <= target after copy).
  console.log('[migrate-data] verification:');
  for (const { source: sourceTable, target: targetTable } of TABLE_MAPPINGS) {
    const sourceExists = await tableExists(source, sourceTable);
    const targetExists = await tableExists(target, targetTable);
    if (!sourceExists || !targetExists) {
      console.log(`  ${sourceTable} -> ${targetTable}: skipped (table missing)`);
      continue;
    }

    try {
      const [s, t] = await Promise.all([
        source.query(`select count(*)::int as n from ${quoteIdent(sourceTable)}`),
        target.query(`select count(*)::int as n from ${quoteQualifiedIdent(targetTable)}`),
      ]);
      const sn = s.rows[0].n as number;
      const tn = t.rows[0].n as number;
      const ok = tn >= sn ? 'OK' : 'MISMATCH';
      console.log(`  ${sourceTable} -> ${targetTable}: source=${sn} target=${tn} ${ok}`);
    } catch (e) {
      console.log(`  ${sourceTable} -> ${targetTable}: count failed (${(e as Error).message})`);
    }
  }

  console.log(`[migrate-data] done: ${totalCopied} rows copied, ${totalSkipped} tables skipped`);

  // Fail if no rows were copied — in dry-run too, since a dry run reporting
  // success while resolving nothing is exactly the failure mode this fixes.
  if (totalCopied === 0) {
    throw new Error('Migration completed but no rows were copied. Check table mappings and database state.');
  }

  return { totalCopied, totalSkipped };
}

async function main() {
  const sourceUrl = process.env.SOURCE_DATABASE_URL;
  const targetUrl = process.env.TARGET_DATABASE_URL;
  const dryRun = process.argv.includes('--dry-run');

  if (!sourceUrl || !targetUrl) {
    console.error('SOURCE_DATABASE_URL and TARGET_DATABASE_URL are required.');
    process.exit(1);
    return;
  }

  const source = new pg.Client({ connectionString: sourceUrl });
  const target = new pg.Client({ connectionString: targetUrl });
  await source.connect();
  await target.connect();
  try {
    await runMigration(source, target, dryRun);
  } finally {
    await source.end().catch(() => undefined);
    await target.end().catch(() => undefined);
  }
}

// Only run when executed as a script, not when imported by tests.
const isMainModule = process.argv[1] && import.meta.url === new URL(process.argv[1], 'file://').href;
if (isMainModule) {
  main().catch((e) => {
    console.error('[migrate-data] failed', e);
    process.exit(1);
  });
}
