import { randomBytes, scrypt as scryptCallback, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { SignJWT, jwtVerify } from 'jose';
import { env } from './config.js';

const scrypt = promisify(scryptCallback);
const textEncoder = new TextEncoder();

export type AuthUserToken = {
  sub: string;
  email: string;
  type: 'access';
};

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const derived = (await scrypt(password, salt, 64)) as Buffer;
  return `${salt}:${derived.toString('hex')}`;
}

export async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  const [salt, existing] = storedHash.split(':');
  if (!salt || !existing) return false;
  const derived = (await scrypt(password, salt, 64)) as Buffer;
  const existingBuffer = Buffer.from(existing, 'hex');
  if (existingBuffer.length !== derived.length) return false;
  return timingSafeEqual(existingBuffer, derived);
}

export async function signAccessToken(
  userId: string,
  email: string,
): Promise<string> {
  return new SignJWT({
    sub: userId,
    email,
    type: 'access',
  })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${env.ACCESS_TOKEN_TTL_MINUTES}m`)
    .sign(textEncoder.encode(env.JWT_ACCESS_SECRET));
}

export async function verifyAccessToken(token: string): Promise<AuthUserToken> {
  const verified = await jwtVerify(token, textEncoder.encode(env.JWT_ACCESS_SECRET));
  return verified.payload as AuthUserToken;
}

export function createRefreshToken(): string {
  return randomBytes(48).toString('base64url');
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
