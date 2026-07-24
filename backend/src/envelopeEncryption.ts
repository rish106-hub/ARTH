import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from 'node:crypto';
import { KeyManagementServiceClient } from '@google-cloud/kms';
import { env } from './config.js';

export type EncryptedPayload = {
  ciphertext: Buffer;
  nonce: Buffer;
  keyVersion: number;
  schemaVersion: number;
};

export type UserDataKey = {
  plaintext: Buffer;
  wrapped: Buffer;
  kmsKeyName: string;
  keyVersion: number;
};

export interface KeyWrappingProvider {
  readonly keyName: string;
  wrap(plaintextKey: Buffer): Promise<Buffer>;
  unwrap(wrappedKey: Buffer): Promise<Buffer>;
}

export class GoogleKmsKeyWrappingProvider implements KeyWrappingProvider {
  readonly keyName: string;
  private readonly client: KeyManagementServiceClient;

  constructor(
    keyName = env.GCP_KMS_KEY_NAME,
    client = new KeyManagementServiceClient(),
  ) {
    if (!keyName) throw new Error('GCP_KMS_KEY_NAME is not configured');
    this.keyName = keyName;
    this.client = client;
  }

  async wrap(plaintextKey: Buffer): Promise<Buffer> {
    const [result] = await this.client.encrypt({
      name: this.keyName,
      plaintext: plaintextKey,
    });
    if (!result.ciphertext) throw new Error('Cloud KMS returned no ciphertext');
    return Buffer.from(result.ciphertext as Uint8Array);
  }

  async unwrap(wrappedKey: Buffer): Promise<Buffer> {
    const [result] = await this.client.decrypt({
      name: this.keyName,
      ciphertext: wrappedKey,
    });
    if (!result.plaintext) throw new Error('Cloud KMS returned no plaintext');
    return Buffer.from(result.plaintext as Uint8Array);
  }
}

export class LocalKeyWrappingProvider implements KeyWrappingProvider {
  readonly keyName = 'local-development-key';
  private readonly key: Buffer;

  constructor(encodedKey = env.USER_KEY_ENCRYPTION_KEY) {
    if (env.NODE_ENV === 'production') {
      throw new Error('Local key wrapping is disabled in production');
    }
    if (!encodedKey) throw new Error('USER_KEY_ENCRYPTION_KEY is not configured');
    this.key = Buffer.from(encodedKey, 'base64');
    if (this.key.length !== 32) {
      throw new Error('USER_KEY_ENCRYPTION_KEY must be 32 base64-encoded bytes');
    }
  }

  async wrap(plaintextKey: Buffer): Promise<Buffer> {
    const nonce = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.key, nonce);
    const ciphertext = Buffer.concat([cipher.update(plaintextKey), cipher.final()]);
    return Buffer.concat([nonce, cipher.getAuthTag(), ciphertext]);
  }

  async unwrap(wrappedKey: Buffer): Promise<Buffer> {
    if (wrappedKey.length < 29) throw new Error('Wrapped key is malformed');
    const nonce = wrappedKey.subarray(0, 12);
    const tag = wrappedKey.subarray(12, 28);
    const ciphertext = wrappedKey.subarray(28);
    const decipher = createDecipheriv('aes-256-gcm', this.key, nonce);
    decipher.setAuthTag(tag);
    return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  }
}

export async function createUserDataKey(
  provider: KeyWrappingProvider,
  keyVersion = 1,
): Promise<UserDataKey> {
  const plaintext = randomBytes(32);
  return {
    plaintext,
    wrapped: await provider.wrap(plaintext),
    kmsKeyName: provider.keyName,
    keyVersion,
  };
}

export function encryptUserPayload(
  dataKey: Buffer,
  context: EncryptionContext,
  value: unknown,
): EncryptedPayload {
  assertDataKey(dataKey);
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', dataKey, nonce);
  cipher.setAAD(contextAad(context));
  const encoded = Buffer.from(JSON.stringify(value), 'utf8');
  const ciphertext = Buffer.concat([cipher.update(encoded), cipher.final()]);
  return {
    ciphertext: Buffer.concat([cipher.getAuthTag(), ciphertext]),
    nonce,
    keyVersion: context.keyVersion,
    schemaVersion: context.schemaVersion,
  };
}

export function decryptUserPayload<T>(
  dataKey: Buffer,
  context: EncryptionContext,
  encrypted: EncryptedPayload,
): T {
  assertDataKey(dataKey);
  if (encrypted.ciphertext.length < 17) throw new Error('Ciphertext is malformed');
  const tag = encrypted.ciphertext.subarray(0, 16);
  const ciphertext = encrypted.ciphertext.subarray(16);
  const decipher = createDecipheriv('aes-256-gcm', dataKey, encrypted.nonce);
  decipher.setAAD(contextAad(context));
  decipher.setAuthTag(tag);
  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return JSON.parse(plaintext.toString('utf8')) as T;
}

export type EncryptionContext = {
  userId: string;
  entityType: string;
  recordId: string;
  keyVersion: number;
  schemaVersion: number;
};

export function blindIndex(namespace: string, normalizedValue: string): Buffer {
  const key = env.DATA_HMAC_KEY ?? env.PAN_HASH_KEY;
  if (!key || key.length < 32) throw new Error('DATA_HMAC_KEY is not configured');
  return createHmac('sha256', key)
    .update(namespace)
    .update('\0')
    .update(normalizedValue)
    .digest();
}

function contextAad(context: EncryptionContext): Buffer {
  return Buffer.from([
    'arth',
    context.userId,
    context.entityType,
    context.recordId,
    String(context.keyVersion),
    String(context.schemaVersion),
  ].join('\0'), 'utf8');
}

function assertDataKey(dataKey: Buffer) {
  if (dataKey.length !== 32) throw new Error('User data key must be 32 bytes');
}
