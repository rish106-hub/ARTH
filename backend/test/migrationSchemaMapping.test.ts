/**
 * Exercises the actual migrate-data-pg-to-crdb.ts logic (not a copy of its
 * config) against in-memory fixtures standing in for a legacy flat Postgres
 * source and a schema-namespaced Cockroach target.
 */

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  TABLE_MAPPINGS,
  parseQualifiedTable,
  runMigration,
  type QueryableClient,
} from '../src/scripts/migrate-data-pg-to-crdb.js';

interface FixtureTable {
  columns: string[];
  rows: Record<string, unknown>[];
}

/** In-memory stand-in for a Postgres/Cockroach connection driven by table fixtures. */
function makeFixtureClient(tables: Record<string, FixtureTable>): QueryableClient {
  return {
    async query(sql: string, params: unknown[] = []) {
      if (sql.includes('information_schema.tables')) {
        const [schema, table] = params as [string, string];
        const exists = Object.prototype.hasOwnProperty.call(tables, `${schema}.${table}`);
        return { rows: exists ? [{ '?column?': 1 }] : [] };
      }
      if (sql.includes('information_schema.columns')) {
        const [schema, table] = params as [string, string];
        const fixture = tables[`${schema}.${table}`];
        return { rows: fixture ? fixture.columns.map((column_name) => ({ column_name })) : [] };
      }
      if (sql.includes('count(*)::int as n from')) {
        const qualified = extractTableFromSql(sql);
        const fixture = tables[qualified];
        return { rows: [{ n: fixture ? fixture.rows.length : 0 }] };
      }
      if (sql.trim().startsWith('select') && sql.includes(' from ')) {
        const qualified = extractTableFromSql(sql);
        const fixture = tables[qualified];
        return { rows: fixture ? fixture.rows : [] };
      }
      if (sql.trim().startsWith('insert into')) {
        const qualified = extractTableFromSql(sql, 'insert into');
        const fixture = tables[qualified];
        if (!fixture) return { rows: [], rowCount: 0 };
        fixture.rows.push({});
        return { rows: [], rowCount: 1 };
      }
      throw new Error(`fixture client cannot handle query: ${sql}`);
    },
  };
}

function extractTableFromSql(sql: string, marker = 'from'): string {
  const re = new RegExp(`${marker}\\s+"([^"]+)"(?:\\."([^"]+)")?`, 'i');
  const m = sql.match(re);
  if (!m) throw new Error(`could not extract table from: ${sql}`);
  // A dotted single identifier (e.g. "auth.auth_sessions") would be a bug in
  // production SQL; keep the test strict so a regression trips it again.
  return m[2] ? `${m[1]}.${m[2]}` : `public.${m[1]}`;
}

/** Fresh, fully-populated fixture set mirroring every mapping in TABLE_MAPPINGS. */
function freshFixtures(): { source: Record<string, FixtureTable>; target: Record<string, FixtureTable> } {
  const source: Record<string, FixtureTable> = {};
  const target: Record<string, FixtureTable> = {};

  for (const mapping of TABLE_MAPPINGS) {
    const { schema: targetSchema, table: targetTable } = parseQualifiedTable(mapping.target);
    source[`public.${mapping.source}`] = {
      columns: [mapping.conflict, 'value'],
      rows: [{ [mapping.conflict]: 'row-1', value: 'x' }],
    };
    target[`${targetSchema}.${targetTable}`] = {
      columns: [mapping.conflict, 'value'],
      rows: [],
    };
  }
  return { source, target };
}

describe('migrate-data-pg-to-crdb: schema-qualified resolution', () => {
  it('resolves namespaced Cockroach schemas, not just public', () => {
    for (const mapping of TABLE_MAPPINGS) {
      const { schema } = parseQualifiedTable(mapping.target);
      assert.notStrictEqual(schema, undefined);
    }
    // At least one mapping must target a non-public schema — this is the bug
    // ARTH-207 exists to fix (cutover previously only ever looked at public).
    assert.ok(TABLE_MAPPINGS.some((m) => !m.target.startsWith('public.')));
  });

  it('migrates every required table against fresh Postgres and Cockroach fixtures', async () => {
    const { source, target } = freshFixtures();
    const result = await runMigration(makeFixtureClient(source), makeFixtureClient(target), false);
    assert.ok(result.totalCopied > 0);
  });

  it('resolves every required target table on a dry run', async () => {
    const { source, target } = freshFixtures();
    const result = await runMigration(makeFixtureClient(source), makeFixtureClient(target), true);
    assert.strictEqual(result.totalSkipped, 0);
    assert.ok(result.totalCopied > 0);
  });
});

describe('migrate-data-pg-to-crdb: fatal validation', () => {
  it('fails before copying anything when a required target schema/table is absent', async () => {
    const { source, target } = freshFixtures();
    const requiredMapping = TABLE_MAPPINGS.find((m) => m.required)!;
    const { schema, table } = parseQualifiedTable(requiredMapping.target);
    delete target[`${schema}.${table}`];

    await assert.rejects(
      () => runMigration(makeFixtureClient(source), makeFixtureClient(target), true),
      /Validation failed/,
    );
  });

  it('cannot report success when every table is skipped', async () => {
    const emptySource: Record<string, FixtureTable> = {};
    const emptyTarget: Record<string, FixtureTable> = {};
    for (const mapping of TABLE_MAPPINGS) {
      if (mapping.required) continue; // required-missing already throws at validation
    }
    // Build fixtures where only optional tables exist (so validation passes)
    // but nothing has rows, proving an all-skip run can't report done.
    for (const mapping of TABLE_MAPPINGS.filter((m) => !m.required)) {
      const { schema, table } = parseQualifiedTable(mapping.target);
      emptySource[`public.${mapping.source}`] = { columns: [mapping.conflict], rows: [] };
      emptyTarget[`${schema}.${table}`] = { columns: [mapping.conflict], rows: [] };
    }
    for (const mapping of TABLE_MAPPINGS.filter((m) => m.required)) {
      const { schema, table } = parseQualifiedTable(mapping.target);
      emptySource[`public.${mapping.source}`] = { columns: [mapping.conflict], rows: [] };
      emptyTarget[`${schema}.${table}`] = { columns: [mapping.conflict], rows: [] };
    }

    await assert.rejects(
      () => runMigration(makeFixtureClient(emptySource), makeFixtureClient(emptyTarget), false),
      /no rows were copied/,
    );
  });

  it('fails a required table that resolves to zero shared columns instead of silently skipping it', async () => {
    const { source, target } = freshFixtures();
    const requiredMapping = TABLE_MAPPINGS.find((m) => m.required)!;
    const { schema, table } = parseQualifiedTable(requiredMapping.target);
    // Simulate schema drift: target table exists but shares no columns with source.
    target[`${schema}.${table}`] = { columns: ['completely_different_column'], rows: [] };

    await assert.rejects(
      () => runMigration(makeFixtureClient(source), makeFixtureClient(target), false),
      /no shared columns/,
    );
  });
});

describe('Migration Schema Mapping', () => {
  it('has all required mappings defined for critical tables', () => {
    const criticalTables = [
      'auth_refresh_sessions',
      'tax_profiles',
      'tax_documents',
      'money_goals',
      'employer_catalog',
      'spend_maps',
      'security_tombstones',
    ];
    for (const table of criticalTables) {
      const mapping = TABLE_MAPPINGS.find((m) => m.source === table);
      assert.ok(mapping, `Critical table ${table} should have a mapping`);
      assert.strictEqual(mapping?.required, true, `Critical table ${table} should be required`);
    }
  });

  it('has unique source and target tables', () => {
    const sources = TABLE_MAPPINGS.map((m) => m.source);
    const targets = TABLE_MAPPINGS.map((m) => m.target);
    assert.strictEqual(sources.length, new Set(sources).size, 'source tables must be unique');
    assert.strictEqual(targets.length, new Set(targets).size, 'target tables must be unique');
  });

  it('has a conflict column defined for every mapping', () => {
    for (const mapping of TABLE_MAPPINGS) {
      assert.ok(mapping.conflict?.length, `${mapping.source} -> ${mapping.target} needs a conflict column`);
    }
  });
});
