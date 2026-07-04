ALTER TABLE tax_documents
    ADD COLUMN IF NOT EXISTS user_label TEXT,
    ADD COLUMN IF NOT EXISTS notes TEXT,
    ADD COLUMN IF NOT EXISTS tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS vault_status TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS review_status TEXT NOT NULL DEFAULT 'not_reviewed',
    ADD COLUMN IF NOT EXISTS confirmed_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS document_events (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    document_id   UUID REFERENCES tax_documents(id) ON DELETE SET NULL,
    event_type    TEXT NOT NULL,
    metadata      JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_events_user_document
    ON document_events(user_id, document_id, created_at desc);

CREATE INDEX IF NOT EXISTS idx_tax_documents_user_fy_vault
    ON tax_documents(user_id, fy, vault_status, updated_at desc);
