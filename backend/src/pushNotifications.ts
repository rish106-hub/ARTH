import { createSign } from 'node:crypto';
import { env } from './config.js';
import { db } from './db.js';
import { decryptDocument } from './security.js';

type FirebaseCredentials = {
  client_email: string;
  private_key: string;
  project_id: string;
};

let credentials: FirebaseCredentials | null | undefined;
let cachedAccessToken: { value: string; expiresAt: number } | null = null;
let accessTokenRequest: Promise<string> | null = null;
let lastClaimsPruneAt = 0;

function getFirebaseCredentials(): FirebaseCredentials | null {
  if (credentials !== undefined) return credentials;
  const encoded = env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!encoded) {
    console.warn('[push] FIREBASE_SERVICE_ACCOUNT_JSON not set; push disabled');
    credentials = null;
    return credentials;
  }
  try {
    const parsed = JSON.parse(
      Buffer.from(encoded, 'base64').toString('utf8'),
    ) as Partial<FirebaseCredentials>;
    if (!parsed.client_email || !parsed.private_key || !parsed.project_id) {
      throw new Error('service account fields are missing');
    }
    credentials = parsed as FirebaseCredentials;
  } catch (error) {
    console.warn('[push] invalid Firebase credentials', (error as Error).message);
    credentials = null;
  }
  return credentials;
}

function encodeJson(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

async function requestAccessToken(
  serviceAccount: FirebaseCredentials,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = [
    encodeJson({ alg: 'RS256', typ: 'JWT' }),
    encodeJson({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  ].join('.');
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const assertion = `${unsigned}.${signer.sign(
    serviceAccount.private_key,
    'base64url',
  )}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const json = await response.json() as {
    access_token?: string;
    expires_in?: number;
    error_description?: string;
  };
  if (!response.ok || !json.access_token) {
    throw new Error(json.error_description ?? `oauth_http_${response.status}`);
  }
  cachedAccessToken = {
    value: json.access_token,
    expiresAt: Date.now() + (json.expires_in ?? 3600) * 1000,
  };
  return json.access_token;
}

async function getAccessToken(
  serviceAccount: FirebaseCredentials,
): Promise<string> {
  if (cachedAccessToken
    && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }
  accessTokenRequest ??= requestAccessToken(serviceAccount)
    .finally(() => {
      accessTokenRequest = null;
    });
  return accessTokenRequest;
}

type FcmErrorBody = {
  error?: {
    code?: number;
    message?: string;
    status?: string;
    details?: Array<{ errorCode?: string }>;
  };
};

async function sendFcmMessage(
  serviceAccount: FirebaseCredentials,
  token: string,
  payload: PushPayload,
): Promise<'delivered' | 'stale'> {
  const accessToken = await getAccessToken(serviceAccount);
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: payload.title, body: payload.body },
          data: payload.data,
        },
      }),
    },
  );
  if (response.ok) return 'delivered';

  const body = await response.json().catch(() => ({})) as FcmErrorBody;
  const errorCode = body.error?.details
    ?.map((detail) => detail.errorCode)
    .find(Boolean);
  if (errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT') {
    return 'stale';
  }
  throw new Error(errorCode ?? body.error?.status ?? `fcm_http_${response.status}`);
}

async function pruneExpiredDeliveryClaims(): Promise<void> {
  const now = Date.now();
  if (now - lastClaimsPruneAt < 24 * 60 * 60 * 1000) return;
  lastClaimsPruneAt = now;
  try {
    await db.query(
      `delete from push_delivery_claims
       where created_at < now() - interval '90 days'`,
    );
  } catch (error) {
    lastClaimsPruneAt = 0;
    console.warn('[push] claim cleanup failed', (error as Error).message);
  }
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  dailyDedupeKey?: string;
}

/// Sends a push notification to every registered device for a user.
/// Best-effort: prunes tokens FCM reports as unregistered/invalid, and never
/// throws — callers (e.g. the spend-map overspend alert) should not fail their
/// own request just because a push could not be delivered.
export async function sendPushToUser(userId: string, payload: PushPayload): Promise<void> {
  const serviceAccount = getFirebaseCredentials();
  if (!serviceAccount) return;

  const { rows } = await db.query(
    `select id, token_ciphertext, token_iv, token_auth_tag
     from device_tokens
     where user_id = $1`,
    [userId],
  );
  if (rows.length === 0) return;

  let deliveryClaimId: string | null = null;
  if (payload.dailyDedupeKey) {
    await pruneExpiredDeliveryClaims();
    const claim = await db.query(
      `insert into push_delivery_claims (user_id, delivery_key, bucket_date)
       values ($1, $2, current_date)
       on conflict (user_id, delivery_key, bucket_date) do nothing
       returning id`,
      [userId, payload.dailyDedupeKey],
    );
    if (claim.rows.length === 0) return;
    deliveryClaimId = claim.rows[0].id;
  }

  const staleTokenIds: string[] = [];
  let delivered = 0;

  await Promise.all(rows.map(async (row: {
    id: string;
    token_ciphertext: string;
    token_iv: string;
    token_auth_tag: string;
  }) => {
    try {
      const token = decryptDocument({
        ciphertext: row.token_ciphertext,
        iv: row.token_iv,
        authTag: row.token_auth_tag,
      }).toString('utf8');
      const result = await sendFcmMessage(serviceAccount, token, payload);
      if (result === 'stale') {
        staleTokenIds.push(row.id);
      } else {
        delivered += 1;
      }
    } catch (error) {
      console.warn('[push] send failed', (error as Error).message);
    }
  }));

  if (staleTokenIds.length > 0) {
    await db.query('delete from device_tokens where id = any($1::uuid[])', [staleTokenIds]);
  }
  if (deliveryClaimId && delivered === 0) {
    await db.query('delete from push_delivery_claims where id = $1', [deliveryClaimId]);
  }
}

export function resetPushNotificationStateForTests(): void {
  if (env.NODE_ENV !== 'test') {
    throw new Error('resetPushNotificationStateForTests is only allowed in test');
  }
  credentials = undefined;
  cachedAccessToken = null;
  accessTokenRequest = null;
  lastClaimsPruneAt = 0;
}
