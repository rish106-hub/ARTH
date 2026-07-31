-- Spend ledger for paid model calls, and a shared merchant→category cache.
--
-- Neither table carries row-level security, unlike the per-user tables. That is
-- deliberate and load-bearing:
--
--   ai_spend_ledger  the budget cap is a single global figure, so the runtime
--                    must SUM across every user's rows. An isolation policy
--                    would silently turn one $1.50 cap into a $1.50 cap per
--                    user. user_id is recorded only to rate-limit a single
--                    account, and cascades away with the account.
--
--   merchant_category_cache  is shared across all users by design — that is the
--                    entire cost saving. It therefore stores no user reference
--                    and no readable merchant text, only a keyed HMAC of the
--                    normalised merchant name (see blindIndex). A plain hash
--                    would be brute-forceable over the small space of real
--                    merchant names; the keyed digest is not.

CREATE TABLE IF NOT EXISTS ai_spend_ledger (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES app_users(id) ON DELETE CASCADE,
    model               TEXT NOT NULL,
    -- Billed token counts as reported by the provider, never estimated.
    input_tokens        BIGINT NOT NULL DEFAULT 0,
    cached_input_tokens BIGINT NOT NULL DEFAULT 0,
    output_tokens       BIGINT NOT NULL DEFAULT 0,
    -- Integer micro-dollars. Money is never stored as a float, and the cap
    -- comparison has to be exact.
    micro_usd           BIGINT NOT NULL DEFAULT 0,
    -- Items classified by this call, for the per-user daily quota.
    items               INTEGER NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ai_spend_ledger_non_negative CHECK (
      input_tokens >= 0
      AND cached_input_tokens >= 0
      AND output_tokens >= 0
      AND micro_usd >= 0
      AND items >= 0
    )
);

-- Serves both the lifetime cap sum and the per-user daily quota.
CREATE INDEX IF NOT EXISTS idx_ai_spend_ledger_created
    ON ai_spend_ledger(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_spend_ledger_user_created
    ON ai_spend_ledger(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS merchant_category_cache (
    merchant_hash   TEXT PRIMARY KEY,
    category        TEXT NOT NULL,
    confidence      TEXT NOT NULL,
    model           TEXT NOT NULL,
    hits            BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT merchant_category_cache_hash_length CHECK (
      length(merchant_hash) BETWEEN 32 AND 128
    ),
    CONSTRAINT merchant_category_cache_category_length CHECK (
      length(category) <= 64
    )
);

REVOKE ALL ON TABLE ai_spend_ledger FROM PUBLIC;
REVOKE ALL ON TABLE merchant_category_cache FROM PUBLIC;
