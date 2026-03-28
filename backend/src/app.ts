import Fastify from 'fastify';
import cors from '@fastify/cors';
import { env } from './config.js';
import { registerRoutes } from './routes.js';

export async function buildApp() {
  const app = Fastify({
    logger: true,
  });

  await app.register(cors, {
    origin: env.CORS_ORIGIN === '*'
      ? true
      : env.CORS_ORIGIN.split(',').map((origin) => origin.trim()),
    credentials: true,
  });

  await app.register(registerRoutes, { prefix: '/v1' });
  return app;
}
