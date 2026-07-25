# ARTH Backend

This backend is the secure API layer between the Flutter app and its PostgreSQL
data store. Neon remains active during the parallel CockroachDB migration.

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
- per-user envelope-encryption primitives
- private GCS document-object storage
- CockroachDB row-level security and ownership constraints

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
- `CURRENT_FY=2025-26`
- `DOCUMENT_ENCRYPTION_KEY` as 32 random bytes, base64 encoded
- `SARVAM_API_KEY` to enable Sarvam Document Intelligence for complex scans
- `SARVAM_API_BASE_URL` defaults to `https://api.sarvam.ai`
- `SARVAM_DOCUMENT_LANGUAGE` defaults to `hi-IN`
- `SARVAM_TIMEOUT_MS` defaults to `480000` (8 minutes) and stays below the mobile 10-minute upload timeout

Fail-fast checks reject wildcard production CORS, non-HTTPS production origins,
matching JWT secrets, placeholder JWT secrets, and out-of-range token or DB
pool settings.

## Neon backup and restore

- Enable Neon point-in-time restore for the production project.
- Before release, confirm latest restore point exists.
- Test restore into a separate branch/project before touching production.
- Keep the ordered files in `backend/sql` as the schema source.
- Never run destructive SQL against production without a verified restore path.

## Incident checklist

- Rotate `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` if token leakage is suspected.
- Revoke refresh sessions in the database for affected users.
- Rotate Railway and Neon credentials if environment access is suspected.
- Check GitHub Dependabot, code scanning, and secret scanning alerts.
- Preserve logs needed for investigation, but do not export passwords, tokens, or raw secrets.

Apply pending Neon migrations from the backend directory:

```bash
npm run migrate
```

Production startup runs the same migration command before accepting traffic.
Applied files and checksums are recorded in `schema_migrations`.

CockroachDB uses its own migration stream:

```bash
DB_DIALECT=cockroach npm run migrate
DB_DIALECT=cockroach npm run verify:cockroach
```

See `../docs/database-architecture.md` before changing production credentials.

If you already have a Neon API key, you can provision a project from the terminal:

```bash
NEON_API_KEY=... npm run provision:neon
```

Run locally:

```bash
npm run dev
```

The Flutter app can be pointed at any deployed backend with:

```text
--dart-define=ARTH_API_BASE_URL=https://YOUR_BACKEND_DOMAIN/v1
```

For Android emulator access or local backend testing, override with:

```bash
flutter run --dart-define=ARTH_API_BASE_URL=http://YOUR_HOST:8787/v1
```

GitHub debug APK builds read the optional repository variable
`ARTH_API_BASE_URL`. Release builds require that variable so signed artifacts
cannot ship without an explicit backend endpoint.
