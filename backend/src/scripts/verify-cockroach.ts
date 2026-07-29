import 'dotenv/config';

import pg from 'pg';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) throw new Error('DATABASE_URL is required');
if (process.env.DB_DIALECT !== 'cockroach') {
  throw new Error('DB_DIALECT=cockroach is required');
}

const expectedSchemas = [
  'public',
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
];

const expectedTables = [
  'public.user_state',
  'auth.users',
  'auth.auth_identities',
  'auth.auth_sessions',
  'auth.devices',
  'auth.user_keyrings',
  'privacy.consents',
  'privacy.data_export_jobs',
  'privacy.deletion_jobs',
  'privacy.security_tombstones',
  'profile.user_profiles',
  'profile.user_preferences',
  'profile.employment_periods',
  'profile.compensation_packages',
  'profile.compensation_components',
  'vault.documents',
  'vault.document_objects',
  'vault.processing_jobs',
  'vault.document_extractions',
  'vault.extracted_facts',
  'vault.document_events',
  'payroll.statements',
  'payroll.line_items',
  'finance.transactions',
  'finance.transaction_corrections',
  'finance.spend_snapshots',
  'tax.tax_years',
  'tax.rule_versions',
  'tax.tax_facts',
  'tax.tax_computations',
  'tax.readiness_items',
  'goals.goals',
  'goals.goal_plans',
  'goals.goal_contributions',
  'reference.employers',
  'reference.financial_categories',
  'reference.payroll_components',
  'payroll.component_aliases',
  'ops.idempotency_keys',
  'ops.sync_revisions',
  'ops.outbox_events',
  'ops.audit_events',
  'ops.schema_migrations',
  'ops.migration_lock',
];

const rlsTables = expectedTables.filter((table) => {
  const schema = table.split('.')[0];
  return !['reference'].includes(schema)
    && ![
      'auth.users',
      'payroll.component_aliases',
      'privacy.security_tombstones',
      'tax.tax_years',
      'tax.rule_versions',
      'ops.audit_events',
      'ops.schema_migrations',
      'ops.migration_lock',
    ].includes(table);
});
rlsTables.push('auth.users');

async function verify() {
  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    const schemas = await client.query<{ schema_name: string }>(
      `select schema_name
       from information_schema.schemata
       where schema_name = any($1::string[])`,
      [expectedSchemas],
    );
    assertSet('schemas', expectedSchemas, schemas.rows.map((row) => row.schema_name));

    const tables = await client.query<{ qualified_name: string }>(
      `select table_schema || '.' || table_name as qualified_name
       from information_schema.tables
       where table_schema = any($1::string[])`,
      [expectedSchemas],
    );
    assertSet('tables', expectedTables, tables.rows.map((row) => row.qualified_name));

    const rls = await client.query<{
      qualified_name: string;
      relrowsecurity: boolean;
      relforcerowsecurity: boolean;
    }>(
      `select n.nspname || '.' || c.relname as qualified_name,
              c.relrowsecurity,
              c.relforcerowsecurity
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = any($1::string[])
         and c.relkind = 'r'`,
      [expectedSchemas],
    );
    const rlsByTable = new Map(rls.rows.map((row) => [row.qualified_name, row]));
    for (const table of rlsTables) {
      const state = rlsByTable.get(table);
      if (!state?.relrowsecurity || !state.relforcerowsecurity) {
        throw new Error(`RLS is not enabled and forced on ${table}`);
      }
    }

    const compositeOwnershipFks = await client.query<{ count: string }>(
      `select count(*)::string as count
       from pg_constraint
       where contype = 'f'
         and array_length(conkey, 1) >= 2`,
    );
    const ownershipFkCount = Number(compositeOwnershipFks.rows[0]?.count ?? 0);
    if (ownershipFkCount < 10) {
      throw new Error(`Expected at least 10 composite ownership FKs, found ${ownershipFkCount}`);
    }

    console.log(JSON.stringify({
      ok: true,
      schemas: expectedSchemas.length,
      tables: expectedTables.length,
      forcedRlsTables: rlsTables.length,
      compositeOwnershipFks: ownershipFkCount,
    }));
  } finally {
    await client.end();
  }
}

function assertSet(label: string, expected: string[], actual: string[]) {
  const actualSet = new Set(actual);
  const missing = expected.filter((item) => !actualSet.has(item));
  if (missing.length) throw new Error(`Missing ${label}: ${missing.join(', ')}`);
}

verify().catch((error) => {
  console.error('[verify-cockroach] failed', error);
  process.exitCode = 1;
});
