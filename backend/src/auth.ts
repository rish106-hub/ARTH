import { FastifyReply, FastifyRequest } from 'fastify';
import { verifyAccessToken } from './security.js';

export async function requireAuth(request: FastifyRequest, reply: FastifyReply) {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    reply.code(401).send({
      code: 'missing_bearer_token',
      message: 'Missing bearer token',
      retryable: false,
    });
    return null;
  }

  try {
    const token = authHeader.replace('Bearer ', '').trim();
    const payload = await verifyAccessToken(token);
    return {
      userId: payload.sub,
      email: payload.email,
    };
  } catch (_) {
    reply.code(401).send({
      code: 'invalid_or_expired_access_token',
      message: 'Invalid or expired access token',
      retryable: false,
    });
    return null;
  }
}
