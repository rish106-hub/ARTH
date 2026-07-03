CREATE TABLE IF NOT EXISTS tax_documents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                  VARCHAR(7) NOT NULL,
    document_type       TEXT NOT NULL,
    original_filename   TEXT NOT NULL,
    mime_type           TEXT NOT NULL,
    byte_size           INTEGER NOT NULL CHECK (byte_size > 0),
    sha256_fingerprint  TEXT NOT NULL,
    ciphertext          TEXT NOT NULL,
    iv                  TEXT NOT NULL,
    auth_tag            TEXT NOT NULL,
    parse_status        TEXT NOT NULL DEFAULT 'metadata_ready',
    parse_summary       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tax_documents_user_fy
    ON tax_documents(user_id, fy, created_at desc);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_documents_user_fy_type_hash
    ON tax_documents(user_id, fy, document_type, sha256_fingerprint);
