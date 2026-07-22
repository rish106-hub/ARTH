CREATE TABLE IF NOT EXISTS money_goals (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    name                    TEXT NOT NULL,
    category                TEXT NOT NULL,
    target_amount           INTEGER NOT NULL CHECK (target_amount > 0),
    current_amount          INTEGER NOT NULL DEFAULT 0 CHECK (current_amount >= 0),
    target_date             DATE NOT NULL,
    monthly_essentials      INTEGER NOT NULL CHECK (monthly_essentials >= 0),
    monthly_family_support  INTEGER NOT NULL DEFAULT 0 CHECK (monthly_family_support >= 0),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_money_goals_user_updated
    ON money_goals(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS employer_catalog (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    normalized_name     TEXT NOT NULL UNIQUE,
    display_name        TEXT NOT NULL,
    source              TEXT NOT NULL CHECK (source IN ('built_in', 'user', 'mca')),
    submitted_by        UUID REFERENCES app_users(id) ON DELETE SET NULL,
    usage_count         INTEGER NOT NULL DEFAULT 1 CHECK (usage_count >= 0),
    approved            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_employer_catalog_display_name
    ON employer_catalog(display_name);

INSERT INTO employer_catalog (normalized_name, display_name, source, approved)
VALUES
  ('accenture', 'Accenture', 'built_in', TRUE),
  ('amazon', 'Amazon', 'built_in', TRUE),
  ('axis bank', 'Axis Bank', 'built_in', TRUE),
  ('cred', 'CRED', 'built_in', TRUE),
  ('deloitte', 'Deloitte', 'built_in', TRUE),
  ('ey', 'EY', 'built_in', TRUE),
  ('flipkart', 'Flipkart', 'built_in', TRUE),
  ('google', 'Google', 'built_in', TRUE),
  ('groww', 'Groww', 'built_in', TRUE),
  ('hcltech', 'HCLTech', 'built_in', TRUE),
  ('hdfc bank', 'HDFC Bank', 'built_in', TRUE),
  ('icici bank', 'ICICI Bank', 'built_in', TRUE),
  ('infosys', 'Infosys', 'built_in', TRUE),
  ('kpmg', 'KPMG', 'built_in', TRUE),
  ('microsoft', 'Microsoft', 'built_in', TRUE),
  ('pwc', 'PwC', 'built_in', TRUE),
  ('razorpay', 'Razorpay', 'built_in', TRUE),
  ('reliance industries', 'Reliance Industries', 'built_in', TRUE),
  ('state bank of india', 'State Bank of India', 'built_in', TRUE),
  ('swiggy', 'Swiggy', 'built_in', TRUE),
  ('tata consultancy services', 'Tata Consultancy Services', 'built_in', TRUE),
  ('tech mahindra', 'Tech Mahindra', 'built_in', TRUE),
  ('wipro', 'Wipro', 'built_in', TRUE),
  ('zomato', 'Zomato', 'built_in', TRUE)
ON CONFLICT (normalized_name) DO NOTHING;
