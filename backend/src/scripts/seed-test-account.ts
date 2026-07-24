import { db } from '../db.js';
import { hashPassword } from '../security.js';

const enabled = process.env.ALLOW_TEST_ACCOUNT_SEED === 'true';
const email = process.env.ARTH_TEST_ACCOUNT_EMAIL ?? 'admin@arth.test';
const name = process.env.ARTH_TEST_ACCOUNT_NAME ?? 'admin';
const password = process.env.ARTH_TEST_ACCOUNT_PASSWORD;

if (!enabled) {
  throw new Error('Set ALLOW_TEST_ACCOUNT_SEED=true to seed the test account.');
}

if (!password) {
  throw new Error('Set ARTH_TEST_ACCOUNT_PASSWORD before seeding.');
}

if (!email.endsWith('@arth.test')) {
  throw new Error('Test account email must use the @arth.test domain.');
}

try {
  const passwordHash = await hashPassword(password);
  const result = await db.query(
    `insert into app_users (
       email, name, password_hash, auth_provider, email_verified
     ) values ($1, $2, $3, 'password', true)
     on conflict (email) do update
       set name = excluded.name,
           password_hash = excluded.password_hash,
           auth_provider = 'password',
           email_verified = true,
           updated_at = now()
     returning id, email, name`,
    [email.toLowerCase(), name, passwordHash],
  );

  const user = result.rows[0];
  await db.query(
    'update auth_refresh_sessions set revoked_at = now() where user_id = $1 and revoked_at is null',
    [user.id],
  );

  console.log(JSON.stringify({
    seeded: true,
    email: user.email,
    name: user.name,
  }));
} finally {
  await db.end?.();
}
