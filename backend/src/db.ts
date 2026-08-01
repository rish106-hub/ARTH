import { AsyncLocalStorage } from 'node:async_hooks';
import { Pool, types } from 'pg';
import { env } from './config.js';

const userTxStorage = new AsyncLocalStorage<DbClient>();

// CockroachDB types every INTEGER column as INT8, which node-postgres returns
// as a STRING to avoid precision loss. Clients (Flutter) parse these fields as
// int, so leaving them as strings throws "String is not a subtype of int".
// Parse INT8 (OID 20) back to a JS number when it fits safely; keep genuinely
// huge values (e.g. unique_rowid ids) as strings so precision is never lost.
types.setTypeParser(20, (value) => {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : value;
});

type QueryResultLike = {
  rowCount: number | null;
  rows: any[];
};

export type Queryable = {
  query: (sql: string, params?: unknown[]) => Promise<QueryResultLike>;
};

export type DbClient = Queryable & {
  release: () => void;
};

export type DbHandle = Queryable & {
  connect: () => Promise<DbClient>;
  end?: () => Promise<void>;
};

const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: env.DB_POOL_MAX,
  idleTimeoutMillis: env.DB_IDLE_TIMEOUT_MS,
  connectionTimeoutMillis: env.DB_CONNECTION_TIMEOUT_MS,
});

pool.on('error', (error: Error) => {
  console.error('[db] idle pool error', error);
});

let activeDb: DbHandle = pool;

const transientDbErrorCodes = new Set([
  '40001',
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

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function isTransientDbError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const directCode = (error as { code?: unknown }).code;
  if (typeof directCode === 'string' && transientDbErrorCodes.has(directCode)) {
    return true;
  }
  const nested = (error as { errors?: unknown; aggregateErrors?: unknown });
  const children = Array.isArray(nested.errors)
    ? nested.errors
    : Array.isArray(nested.aggregateErrors)
      ? nested.aggregateErrors
      : [];
  return children.some(isTransientDbError);
}

async function withDbRetry<T>(operation: () => Promise<T>): Promise<T> {
  const delays = [150, 500, 1200];
  let lastError: unknown;

  for (let attempt = 0; attempt <= delays.length; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (!isTransientDbError(error) || attempt === delays.length) {
        throw error;
      }
      await delay(delays[attempt]);
    }
  }

  throw lastError;
}

export function getUserTxClient(): DbClient | undefined {
  return userTxStorage.getStore();
}

export async function setUserDbContext(
  client: Queryable,
  userId: string,
): Promise<void> {
  const safeUserId = userId.replaceAll("'", "''");
  await client.query(`select set_config('application_name', 'arth.${safeUserId}', true)`);
}

export async function withUserContext<T>(
  userId: string,
  operation: () => Promise<T>,
): Promise<T> {
  return runSerializableTransaction(async (client) => {
    await client.query('set transaction isolation level read committed');
    await setUserDbContext(client, userId);
    return userTxStorage.run(client, operation);
  });
}

export async function runAsSystem<T>(operation: () => Promise<T>): Promise<T> {
  return runSerializableTransaction(async (client) => {
    await client.query('set transaction isolation level read committed');
    await client.query(`select set_config('arth.system', 'true', true)`);
    return userTxStorage.run(client, operation);
  });
}

export async function runSerializableTransaction<T>(
  operation: (client: DbClient) => Promise<T>,
  handle: DbHandle = db,
): Promise<T> {
  const existingClient = userTxStorage.getStore();
  if (existingClient) {
    return operation(existingClient);
  }

  const delays = [50, 150, 500, 1_200];
  let lastError: unknown;

  for (let attempt = 0; attempt <= delays.length; attempt += 1) {
    const client = await handle.connect();
    try {
      await client.query('begin');
      const result = await userTxStorage.run(client, () => operation(client));
      await client.query('commit');
      return result;
    } catch (error) {
      lastError = error;
      await client.query('rollback').catch(() => undefined);
      const code = typeof error === 'object' && error
        ? (error as { code?: unknown }).code
        : undefined;
      if (code !== '40001' || attempt === delays.length) throw error;
      await delay(delays[attempt]);
    } finally {
      client.release();
    }
  }

  throw lastError;
}

function queryThroughUserTx(
  sql: string,
  params?: unknown[],
): Promise<QueryResultLike> {
  const txClient = userTxStorage.getStore();
  if (txClient) {
    return txClient.query(sql, params);
  }
  return withDbRetry(() => activeDb.query(sql, params));
}

export const db: DbHandle = {
  query(sql, params) {
    return queryThroughUserTx(sql, params);
  },
  connect() {
    return withDbRetry(() => activeDb.connect());
  },
  end() {
    return activeDb.end?.() ?? Promise.resolve();
  },
};

export function setDbForTests(testDb: DbHandle) {
  if (env.NODE_ENV !== 'test') {
    throw new Error('setDbForTests is only allowed in test');
  }
  activeDb = testDb;
}

export function resetDbForTests() {
  if (env.NODE_ENV !== 'test') {
    throw new Error('resetDbForTests is only allowed in test');
  }
  activeDb = pool;
}
