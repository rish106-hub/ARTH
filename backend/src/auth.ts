import { FastifyReply, FastifyRequest } from 'fastify';
import { db } from './db.js';
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
    if (payload.sid) {
      const activeSession = await db.query(
        `select 1
         from auth_refresh_sessions
         where id = $1
           and user_id = $2
           and revoked_at is null
           and expires_at > now()`,
        [payload.sid, payload.sub],
      );
      if (!activeSession.rowCount) throw new Error('Session revoked');
    }
    return {
      userId: payload.sub,
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
