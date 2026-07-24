# ARTH database architecture

## Current state

ARTH keeps the existing Neon schema active while the CockroachDB schema is
built and verified in parallel. Do not point Railway at CockroachDB until the
data-copy and API-repository migration is complete.

The CockroachDB source of truth is:

```text
backend/sql/cockroach/001_secure_schema.sql
```

It creates separate auth, privacy, profile, document, payroll, finance, tax,
goal, reference and operations schemas.

## Ownership rules

- Every private row has `user_id`.
- Private child tables use composite foreign keys beginning with `user_id`.
- Cross-user parent-child links fail at the database boundary.
- User indexes begin with `user_id`.
- Forced row-level security checks the authenticated user placed in
  `application_name` as `arth.<user UUID>`.
- Runtime connections must use `arth_auth_runtime` or `arth_app_runtime`.
- Migration credentials must never be used by the API.

## Encryption rules

- CockroachDB and GCS hold ciphertext for PII and financial payloads.
- Each user receives a random 256-bit data key.
- GCP Cloud KMS wraps the user key.
- AES-256-GCM AAD binds data to user, entity, record and schema version.
- HMAC blind indexes support login, duplicate detection and canonical matching.
- Plaintext is limited to ownership IDs, operational state, timestamps and
  non-sensitive reference catalogs.
- Raw SMS remains on-device.
- GCS object names are random and contain no filenames or user information.

## Development validation

Start a disposable CockroachDB node:

```bash
docker run --rm -d --name arth-cockroach-test -p 26258:26257 \
  cockroachdb/cockroach:v26.2.1 start-single-node --insecure
```

Apply and verify:

```bash
cd backend
DB_DIALECT=cockroach \
DATABASE_URL='postgresql://root@127.0.0.1:26258/defaultdb?sslmode=disable' \
npm run migrate

DB_DIALECT=cockroach \
DATABASE_URL='postgresql://root@127.0.0.1:26258/defaultdb?sslmode=disable' \
npm run verify:cockroach
```

## Production variables

```text
DB_DIALECT=cockroach
DATABASE_URL=...sslmode=verify-full
GCP_KMS_KEY_NAME=projects/.../locations/asia-south1/keyRings/.../cryptoKeys/...
GCS_DOCUMENT_BUCKET=...
GCS_LOCATION=asia-south1
DATA_HMAC_KEY=64-or-more-random-characters
```

Keep `PAN_ENCRYPTION_KEY` and `DOCUMENT_ENCRYPTION_KEY` until every legacy row
has been decrypted once and re-encrypted with its user's data key.

## Cutover gates

1. Verify Cockroach managed backup and an independent encrypted GCS backup.
2. Copy users while preserving IDs and timestamps.
3. Re-encrypt each legacy private field and document with a per-user key.
4. Copy only approved reference data. Exclude demo tables and test accounts.
5. Compare source and target counts, ownership, hashes and sampled decryptions.
6. Freeze Neon writes and copy the final delta.
7. Run `npm run verify:cockroach`.
8. Run auth, document, payslip, tax, spending, goal and deletion smoke tests.
9. Switch Railway credentials.
10. Keep Neon read-only for seven days, then delete it and rotate credentials.

No cutover is allowed while any gate fails.
