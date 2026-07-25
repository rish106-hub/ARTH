CREATE TABLE IF NOT EXISTS push_delivery_claims (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    delivery_key    TEXT NOT NULL,
    bucket_date     DATE NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, delivery_key, bucket_date)
);

CREATE INDEX IF NOT EXISTS idx_push_delivery_claims_created
    ON push_delivery_claims(created_at DESC);
