CREATE TABLE IF NOT EXISTS spend_maps (
    user_id                      UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
    window_start                 TIMESTAMPTZ NOT NULL,
    window_end                   TIMESTAMPTZ NOT NULL,
    generated_at                 TIMESTAMPTZ NOT NULL,
    monthly_income               INTEGER NOT NULL CHECK (monthly_income >= 0),
    monthly_spend                INTEGER NOT NULL CHECK (monthly_spend >= 0),
    realistic_monthly_savings    INTEGER NOT NULL CHECK (realistic_monthly_savings >= 0),
    spend_by_category            JSONB NOT NULL DEFAULT '{}'::jsonb,
    monthly_trend                JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spend_maps_updated
    ON spend_maps(updated_at DESC);
