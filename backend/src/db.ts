import { neonConfig, Pool } from '@neondatabase/serverless';
import ws from 'ws';
import { env } from './config.js';

neonConfig.webSocketConstructor = ws;

export const db = new Pool({
  connectionString: env.DATABASE_URL,
});
