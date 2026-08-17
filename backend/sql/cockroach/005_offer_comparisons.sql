-- CockroachDB counterpart of 020_offer_comparisons.sql.
--
-- Lives in the payroll schema, which already owns compensation records
-- (payroll.statements, payroll.line_items). An offer comparison is a decision
-- about compensation, so it belongs beside them rather than in the vault, which
-- holds documents rather than conclusions drawn from them.
--
-- Session state is encrypted at rest for the same reason as on Postgres: the
-- payload holds normalized salary figures, and no readable salary figure is
-- stored anywhere else in this schema either. Here it is BYTES with a separate
-- nonce, matching how payroll.statements carries its own payload, rather than
-- the JSONB envelope the flat Postgres schema uses.

CREATE TABLE IF NOT EXISTS payroll.offer_comparisons (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    fy                  STRING NOT NULL,
    status              STRING NOT NULL DEFAULT 'questions_pending',
    -- {comparison, questions, answers, advice}, AES-GCM.
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    -- SHA-256 over the normalized offers plus the answers, so the one paid step
    -- in this feature is skipped when its inputs have not changed.
    advice_fingerprint  BYTES,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    CONSTRAINT offer_comparison_status_check CHECK (
      status IN ('questions_pending', 'answered', 'advised')
    ),
    CONSTRAINT offer_comparison_fy_check CHECK (length(fy) <= 16)
);

CREATE INDEX IF NOT EXISTS idx_offer_comparisons_user_created
    ON payroll.offer_comparisons(user_id, created_at DESC);

-- Which stored offer letters a session compares. The composite foreign keys are
-- what make deleting a document cascade the session that depended on it away,
-- so a comparison can never outlive one of its own inputs.
CREATE TABLE IF NOT EXISTS payroll.offer_comparison_offers (
    user_id         UUID NOT NULL,
    comparison_id   UUID NOT NULL,
    document_id     UUID NOT NULL,
    position        INT4 NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, comparison_id, document_id),
    FOREIGN KEY (user_id, comparison_id)
      REFERENCES payroll.offer_comparisons(user_id, id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    CONSTRAINT offer_comparison_offer_position_check CHECK (
      position BETWEEN 0 AND 9
    ),
    UNIQUE (user_id, comparison_id, position)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE payroll.offer_comparisons TO arth_app_runtime;
GRANT SELECT, INSERT, DELETE ON TABLE payroll.offer_comparison_offers TO arth_app_runtime;
