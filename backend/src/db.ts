import { Pool } from 'pg';
import { env } from './config.js';

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

function isTransientDbError(error: unknown): boolean {
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

export const db: DbHandle = {
  query(sql, params) {
    return withDbRetry(() => activeDb.query(sql, params));
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
