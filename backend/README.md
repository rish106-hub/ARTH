# ARTH Backend

This backend is the secure API layer between the Flutter app and Neon.

## Responsibilities

- email/password sign-up and sign-in
- password hashing with `scrypt`
- short-lived JWT access tokens
- refresh-token rotation with hashed storage
- user profile storage
- tax-result storage
- done-gap storage

## Setup

```bash
cd backend
cp .env.example .env
npm install
```

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
http://10.0.2.2:8787/v1
```

for Android emulator access. Override with:

```bash
flutter run --dart-define=ARTH_API_BASE_URL=http://YOUR_HOST:8787/v1
```
