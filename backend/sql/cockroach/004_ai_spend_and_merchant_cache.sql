-- CockroachDB counterpart of 018_ai_spend_and_merchant_cache.sql.
--
-- Both tables are intentionally global rather than user-isolated:
--
--   ai_spend_ledger  the budget cap is one global figure, so the runtime must
--                    SUM across every user's rows. A row-level isolation policy
--                    would silently turn a single $1.50 cap into $1.50 per
--                    user. user_id exists only to rate-limit one account and
--                    cascades away with it.
--
--   merchant_category_cache  is shared across all users by design — that sharing
--                    is the cost saving. It holds no user reference and no
--                    readable merchant text, only a keyed HMAC of the
--                    normalised merchant name (see blindIndex). An unkeyed hash
--                    would be brute-forceable across the small space of real
--                    merchant names.

CREATE TABLE IF NOT EXISTS ai_spend_ledger (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    model               STRING NOT NULL,
    input_tokens        INT8 NOT NULL DEFAULT 0,
    cached_input_tokens INT8 NOT NULL DEFAULT 0,
    output_tokens       INT8 NOT NULL DEFAULT 0,
    micro_usd           INT8 NOT NULL DEFAULT 0,
    items               INT4 NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ai_spend_ledger_non_negative CHECK (
      input_tokens >= 0
      AND cached_input_tokens >= 0
      AND output_tokens >= 0
      AND micro_usd >= 0
      AND items >= 0
    )
);

CREATE INDEX IF NOT EXISTS idx_ai_spend_ledger_created
    ON ai_spend_ledger(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_spend_ledger_user_created
    ON ai_spend_ledger(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS merchant_category_cache (
    merchant_hash   STRING PRIMARY KEY,
    category        STRING NOT NULL,
    confidence      STRING NOT NULL,
    model           STRING NOT NULL,
    hits            INT8 NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT merchant_category_cache_hash_length CHECK (
      length(merchant_hash) BETWEEN 32 AND 128
    ),
    CONSTRAINT merchant_category_cache_category_length CHECK (
      length(category) <= 64
    )
);

GRANT SELECT, INSERT ON TABLE ai_spend_ledger TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE ON TABLE merchant_category_cache TO arth_app_runtime;
