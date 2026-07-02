# ARTH Backend

This backend is the secure API layer between the Flutter app and Neon.

## Responsibilities

- email/password sign-up and sign-in
- password hashing with `scrypt`
- short-lived JWT access tokens
- refresh-token rotation with hashed storage
- security headers via Fastify Helmet
- explicit production CORS allow-list
- rate limits on auth and data routes
- user profile storage
- tax-result storage
- done-gap storage

## Setup

```bash
cd backend
cp .env.example .env
npm install
```

For production, set `NODE_ENV=production`, use 64+ character random JWT
secrets from a secret manager, and set `CORS_ORIGIN` to explicit trusted
origins. Wildcard CORS is rejected in production.

## Production checklist

Railway variables:

- `NODE_ENV=production`
- `DATABASE_URL` from Neon with TLS enabled
- `JWT_ACCESS_SECRET` as a real 64+ character random secret
- `JWT_REFRESH_SECRET` as a different 64+ character random secret
- `CORS_ORIGIN` as comma-separated HTTPS app origins, never `*`
- `ACCESS_TOKEN_TTL_MINUTES=15`
- `REFRESH_TOKEN_TTL_DAYS=30`
- `DB_POOL_MAX=5`
- `DB_IDLE_TIMEOUT_MS=30000`
- `DB_CONNECTION_TIMEOUT_MS=10000`
- `CURRENT_FY=2026-27`

Fail-fast checks reject wildcard production CORS, non-HTTPS production origins,
matching JWT secrets, placeholder JWT secrets, and out-of-range token or DB
pool settings.

## Neon backup and restore

- Enable Neon point-in-time restore for the production project.
- Before release, confirm latest restore point exists.
- Test restore into a separate branch/project before touching production.
- Keep `backend/sql/001_init.sql` as the schema source for fresh environments.
- Never run destructive SQL against production without a verified restore path.

## Incident checklist

- Rotate `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` if token leakage is suspected.
- Revoke refresh sessions in the database for affected users.
- Rotate Railway and Neon credentials if environment access is suspected.
- Check GitHub Dependabot, code scanning, and secret scanning alerts.
- Preserve logs needed for investigation, but do not export passwords, tokens, or raw secrets.

Apply the Neon schema in:

```bash
backend/sql/001_init.sql
```

Example:

```bash
psql "$DATABASE_URL" -f backend/sql/001_init.sql
```

If you already have a Neon API key, you can provision a project from the terminal:

```bash
NEON_API_KEY=... npm run provision:neon
```

Run locally:

```bash
npm run dev
```

The Flutter app defaults to:

```text
https://arth-production-aaca.up.railway.app/v1
```

For Android emulator access or local backend testing, override with:

```bash
flutter run --dart-define=ARTH_API_BASE_URL=http://YOUR_HOST:8787/v1
```
