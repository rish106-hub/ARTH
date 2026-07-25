import { getApps, initializeApp, cert, type App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { db } from './db.js';
import { decryptDocument } from './security.js';

/// Lazily initializes the Firebase Admin app from FIREBASE_SERVICE_ACCOUNT_JSON
/// (the full service-account JSON, base64-encoded). Returns null when the env
/// var is missing/invalid so callers can no-op instead of crashing — mirrors
/// how the Gemini integration degrades when GEMINI_API_KEY is absent.
let app: App | null | undefined;

function getFirebaseApp(): App | null {
  if (app !== undefined) return app;
  const encoded = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!encoded) {
    console.warn('[push] FIREBASE_SERVICE_ACCOUNT_JSON not set; push disabled');
    app = null;
    return app;
  }
  try {
    const json = JSON.parse(Buffer.from(encoded, 'base64').toString('utf8'));
    app = getApps()[0] ?? initializeApp({ credential: cert(json) });
  } catch (error) {
    console.warn('[push] failed to init firebase-admin', (error as Error).message);
    app = null;
  }
  return app;
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
  const firebaseApp = getFirebaseApp();
  if (!firebaseApp) return;

  const { rows } = await db.query(
    `select id, token_ciphertext, token_iv, token_auth_tag
     from device_tokens
     where user_id = $1`,
    [userId],
  );
  if (rows.length === 0) return;

  let deliveryClaimId: string | null = null;
  if (payload.dailyDedupeKey) {
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

  const messaging = getMessaging(firebaseApp);
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
      await messaging.send({
        token,
        notification: { title: payload.title, body: payload.body },
        data: payload.data,
      });
      delivered += 1;
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (code === 'messaging/registration-token-not-registered'
        || code === 'messaging/invalid-registration-token') {
        staleTokenIds.push(row.id);
      } else {
        console.warn('[push] send failed', code ?? (error as Error).message);
      }
    }
  }));

  if (staleTokenIds.length > 0) {
    await db.query('delete from device_tokens where id = any($1::uuid[])', [staleTokenIds]);
  }
  if (deliveryClaimId && delivered === 0) {
    await db.query('delete from push_delivery_claims where id = $1', [deliveryClaimId]);
  }
}
