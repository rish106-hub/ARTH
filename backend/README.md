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
