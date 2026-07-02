import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import { ZodError } from 'zod';
import { env } from './config.js';
import { registerRoutes } from './routes.js';

export async function buildApp() {
  const app = Fastify({
    logger: {
      redact: {
        censor: '[redacted]',
        paths: [
          'req.headers.authorization',
          'req.headers.cookie',
          'request.headers.authorization',
          'request.headers.cookie',
          'headers.authorization',
          'headers.cookie',
          '*.password',
          '*.refreshToken',
          '*.accessToken',
          '*.token',
        ],
      },
    },
    bodyLimit: 100 * 1024,
  });

  await app.register(helmet);

  const allowedOrigins = env.CORS_ORIGIN.split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  await app.register(cors, {
    origin: (origin, callback) => {
      if (!origin) {
        callback(null, true);
        return;
      }
      if (env.CORS_ORIGIN === '*' && env.NODE_ENV !== 'production') {
        callback(null, true);
        return;
      }
      callback(null, allowedOrigins.includes(origin));
    },
    credentials: false,
  });

  app.setErrorHandler((error, request, reply) => {
    if (error instanceof ZodError) {
      reply.code(400).send({ message: 'Invalid request' });
      return;
    }

    const appError = error as {
      statusCode?: number;
      headers?: Record<string, string | number | string[]>;
    };
    const statusCode = appError.statusCode ?? 500;
    const headers = appError.headers;
    if (headers) {
      reply.headers(headers);
    }
    if (statusCode < 500) {
      const message = statusCode === 429
        ? 'Too many requests'
        : statusCode === 413
          ? 'Request body too large'
          : 'Request failed';
      reply.code(statusCode).send({ message });
      return;
    }

    request.log.error(error);
    reply.code(500).send({ message: 'Internal server error' });
  });

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).send({ message: 'Not found' });
  });

  await app.register(registerRoutes, { prefix: '/v1' });
  return app;
}
