-- The pre-release table contains no production registrations. Recreate it
-- before launch so a raw FCM token is never persisted.
DROP TABLE IF EXISTS device_tokens;

CREATE TABLE device_tokens (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token_fingerprint   TEXT NOT NULL UNIQUE,
    token_ciphertext    TEXT NOT NULL,
    token_iv            TEXT NOT NULL,
    token_auth_tag      TEXT NOT NULL,
    platform            TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_device_tokens_user
    ON device_tokens(user_id, last_seen_at DESC);
