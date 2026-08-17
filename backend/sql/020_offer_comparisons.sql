-- Multi-offer comparison sessions.
--
-- A session holds one candidate's normalized comparison across several stored
-- offer letters, the questions selected for them, their answers, and the cached
-- verdict and negotiation advice.
--
-- Session state is encrypted at rest. This is not belt-and-braces: the state
-- holds normalized salary figures, and tax_documents already refuses to keep
-- extracted salary fields in readable JSONB (see storedParseSummary, which
-- encrypts them into the parse summary). A plaintext comparison column would
-- quietly undo that, so the whole session payload goes through encryptDocument
-- and lands as an AES-GCM envelope of {ciphertext, iv, authTag}.
--
-- One envelope rather than one per stage, because every read wants the whole
-- session and a single decrypt is simpler than four. The columns kept outside
-- the envelope are only the ones the runtime has to filter or compare on.

CREATE TABLE IF NOT EXISTS offer_comparisons (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                  TEXT NOT NULL,
    -- questions_pending  offers normalized, questions selected, nothing answered
    -- answered           answers stored, advice not yet generated
    -- advised            verdict and negotiation advice cached in the envelope
    status              TEXT NOT NULL DEFAULT 'questions_pending',
    -- AES-GCM envelope of {comparison, questions, answers, advice}.
    state_encrypted     JSONB NOT NULL,
    -- SHA-256 over the normalized offers plus the answers. The advice call is
    -- the only paid step in this feature, so it is skipped when the inputs are
    -- unchanged. Null until advice has been generated once.
    advice_fingerprint  TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT offer_comparisons_status_check CHECK (
      status IN ('questions_pending', 'answered', 'advised')
    ),
    CONSTRAINT offer_comparisons_fy_length CHECK (length(fy) <= 16),
    CONSTRAINT offer_comparisons_fingerprint_length CHECK (
      advice_fingerprint IS NULL OR length(advice_fingerprint) = 64
    )
);

CREATE INDEX IF NOT EXISTS idx_offer_comparisons_user_created
    ON offer_comparisons(user_id, created_at DESC);

-- Which stored offer letters a session compares.
--
-- A real foreign key rather than document ids inside the envelope, so that
-- deleting an offer letter from the vault cascades the session away with it. A
-- comparison that silently outlives one of its inputs would keep answering with
-- a number the user believes they deleted.
CREATE TABLE IF NOT EXISTS offer_comparison_offers (
    comparison_id   UUID NOT NULL REFERENCES offer_comparisons(id) ON DELETE CASCADE,
    document_id     UUID NOT NULL REFERENCES tax_documents(id) ON DELETE CASCADE,
    -- Duplicated from the parent so row-level security can be enforced here too,
    -- rather than trusting a join to have been written correctly.
    user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    -- Stable display order, so "Offer A" means the same thing on every screen.
    position        INTEGER NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (comparison_id, document_id),
    CONSTRAINT offer_comparison_offers_position_check CHECK (
      position BETWEEN 0 AND 9
    ),
    UNIQUE (comparison_id, position)
);

CREATE INDEX IF NOT EXISTS idx_offer_comparison_offers_document
    ON offer_comparison_offers(document_id);

ALTER TABLE offer_comparisons ENABLE ROW LEVEL SECURITY;
ALTER TABLE offer_comparisons FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON offer_comparisons;
CREATE POLICY tenant_isolation ON offer_comparisons
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE offer_comparisons FROM PUBLIC;

ALTER TABLE offer_comparison_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE offer_comparison_offers FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON offer_comparison_offers;
CREATE POLICY tenant_isolation ON offer_comparison_offers
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE offer_comparison_offers FROM PUBLIC;
