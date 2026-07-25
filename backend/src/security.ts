import {
  createCipheriv,
  createHash,
  createHmac,
  randomBytes,
  createDecipheriv,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { Algorithm, hash as argonHash, verify as argonVerify } from '@node-rs/argon2';
import { promisify } from 'node:util';
import { SignJWT, jwtVerify } from 'jose';
import { env } from './config.js';

const scrypt = promisify(scryptCallback);
const textEncoder = new TextEncoder();

export type AuthUserToken = {
  sub: string;
  sid?: string;
  sv: number;
  type: 'access';
};

export async function hashPassword(password: string): Promise<string> {
  return argonHash(password, {
    algorithm: Algorithm.Argon2id,
    memoryCost: 65_536,
    timeCost: 3,
    parallelism: 1,
    outputLen: 32,
  });
}

async function verifyLegacyScryptPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  const [storedSalt, existing] = storedHash.split(':');
  if (!storedSalt || !existing) return false;
  const derived = (await scrypt(password, storedSalt, 64)) as Buffer;
  const existingBuffer = Buffer.from(existing, 'hex');
  if (existingBuffer.length !== derived.length) return false;
  return timingSafeEqual(existingBuffer, derived);
}

export async function verifyPassword(
  password: string,
  storedHash: string,
): Promise<boolean> {
  if (storedHash.startsWith('$argon2')) {
    return argonVerify(storedHash, password);
  }
  return verifyLegacyScryptPassword(password, storedHash);
}

export function passwordNeedsRehash(storedHash: string): boolean {
  return !storedHash.startsWith('$argon2id$');
}

export async function signAccessToken(
  userId: string,
  sessionId?: string,
): Promise<string> {
  return new SignJWT({
    sub: userId,
    ...(sessionId ? { sid: sessionId } : {}),
    sv: 1,
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

export type EncryptedSecret = {
  ciphertext: string;
  iv: string;
  authTag: string;
};

export function encryptPan(pan: string): EncryptedSecret {
  const key = panEncryptionKey();
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([
    cipher.update(pan, 'utf8'),
    cipher.final(),
  ]);
  return {
    ciphertext: ciphertext.toString('base64'),
    iv: iv.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
  };
}

export function encryptDocument(bytes: Buffer): EncryptedSecret {
  const key = documentEncryptionKey();
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(bytes), cipher.final()]);
  return {
    ciphertext: ciphertext.toString('base64'),
    iv: iv.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
  };
}

export function decryptDocument(secret: EncryptedSecret): Buffer {
  const key = documentEncryptionKey();
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(secret.iv, 'base64'),
  );
  decipher.setAuthTag(Buffer.from(secret.authTag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(secret.ciphertext, 'base64')),
    decipher.final(),
  ]);
}

export function hashPan(pan: string): string {
  const key = env.PAN_HASH_KEY;
  if (!key || key.length < 32) {
    throw new Error('PAN_HASH_KEY is not configured');
  }
  return createHmac('sha256', key).update(pan).digest('hex');
}

export function hashDeviceToken(token: string): string {
  return createHmac('sha256', documentEncryptionKey())
    .update('arth-device-token-v1\0')
    .update(token)
    .digest('hex');
}

function panEncryptionKey(): Buffer {
  const raw = env.PAN_ENCRYPTION_KEY;
  if (!raw) throw new Error('PAN_ENCRYPTION_KEY is not configured');
  const key = Buffer.from(raw, 'base64');
  if (key.length !== 32) {
    throw new Error('PAN_ENCRYPTION_KEY must be 32 base64-encoded bytes');
  }
  return key;
}

function documentEncryptionKey(): Buffer {
  const raw = env.DOCUMENT_ENCRYPTION_KEY;
  if (!raw) throw new Error('DOCUMENT_ENCRYPTION_KEY is not configured');
  const key = Buffer.from(raw, 'base64');
  if (key.length !== 32) {
    throw new Error('DOCUMENT_ENCRYPTION_KEY must be 32 base64-encoded bytes');
  }
  return key;
}
