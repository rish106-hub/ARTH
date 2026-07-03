CREATE TABLE IF NOT EXISTS user_private_identity (
    user_id                 UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
    pan_ciphertext          TEXT,
    pan_iv                  TEXT,
    pan_auth_tag            TEXT,
    pan_last4               CHAR(4),
    pan_last_char           CHAR(1),
    pan_fingerprint         TEXT,
    pan_consent_version     TEXT,
    pan_consented_at        TIMESTAMPTZ,
    pan_deleted_at          TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_private_identity_pan_fingerprint
    ON user_private_identity(pan_fingerprint)
    WHERE pan_fingerprint IS NOT NULL;
