import { neonConfig, Pool } from '@neondatabase/serverless';
import ws from 'ws';
import { env } from './config.js';

neonConfig.webSocketConstructor = ws;

type QueryResultLike = {
  rowCount: number | null;
  rows: any[];
};

type Queryable = {
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
});

pool.on('error', (error: Error) => {
  console.error('[db] idle pool error', error);
});

let activeDb: DbHandle = pool;

export const db: DbHandle = {
  query(sql, params) {
    return activeDb.query(sql, params);
  },
  connect() {
    return activeDb.connect();
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
