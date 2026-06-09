import { FastifyReply, FastifyRequest } from 'fastify';
import { verifyAccessToken } from './security.js';

export async function requireAuth(request: FastifyRequest, reply: FastifyReply) {
  const authHeader = request.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    reply.code(401).send({ message: 'Missing bearer token' });
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
    reply.code(401).send({ message: 'Invalid or expired access token' });
    return null;
  }
}
