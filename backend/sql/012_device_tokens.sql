CREATE TABLE IF NOT EXISTS device_tokens (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fcm_token           TEXT NOT NULL,
    platform            TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user
    ON device_tokens(user_id, last_seen_at DESC);
