import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import multipart from '@fastify/multipart';
import { ZodError } from 'zod';
import { env } from './config.js';
import { isTransientDbError } from './db.js';
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
  await app.register(multipart, {
    limits: {
      files: 1,
      fileSize: 8 * 1024 * 1024,
      fields: 8,
    },
  });

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
      reply.code(400).send({
        code: 'invalid_request',
        message: 'Invalid request',
        retryable: false,
      });
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
      reply.code(statusCode).send({
        code: statusCode === 429
          ? 'too_many_requests'
          : statusCode === 413
            ? 'request_body_too_large'
            : 'request_failed',
        message,
        retryable: false,
      });
      return;
    }

    if (isTransientDbError(error)) {
      request.log.warn(error, 'transient backend dependency failure');
      reply.code(503).send({
        code: 'backend_temporarily_unavailable',
        message: 'Service temporarily unavailable',
        retryable: true,
      });
      return;
    }

    request.log.error(error);
    reply.code(500).send({
      code: 'internal_server_error',
      message: 'Internal server error',
      retryable: true,
    });
  });

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).send({
      code: 'not_found',
      message: 'Not found',
      retryable: false,
    });
  });

  await app.register(registerRoutes, { prefix: '/v1' });
  return app;
}
