CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS app_users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email               TEXT NOT NULL UNIQUE,
    name                TEXT NOT NULL,
    phone_e164          TEXT,
    avatar_initials     VARCHAR(2),
    avatar_color        TEXT,
    password_hash       TEXT NOT NULL,
    email_verified      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS auth_refresh_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token_hash          TEXT NOT NULL UNIQUE,
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ,
    user_agent          TEXT,
    ip_address          TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tax_profiles (
    user_id                     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                          VARCHAR(7) NOT NULL,
    name                        TEXT NOT NULL,
    email                       TEXT NOT NULL,
    annual_ctc                  INTEGER NOT NULL CHECK (annual_ctc >= 0),
    employment_type             TEXT NOT NULL CHECK (employment_type IN ('salaried', 'selfEmployed')),
    city                        TEXT NOT NULL,
    is_metro_city               BOOLEAN NOT NULL DEFAULT FALSE,
    pays_rent                   BOOLEAN NOT NULL DEFAULT FALSE,
    monthly_rent                INTEGER NOT NULL DEFAULT 0,
    has_hra                     BOOLEAN NOT NULL DEFAULT FALSE,
    invested_80c                INTEGER NOT NULL DEFAULT 0,
    has_home_loan               BOOLEAN NOT NULL DEFAULT FALSE,
    property_type               TEXT,
    home_loan_interest          INTEGER NOT NULL DEFAULT 0,
    has_nps                     BOOLEAN NOT NULL DEFAULT FALSE,
    nps_extra_contribution      INTEGER NOT NULL DEFAULT 0,
    has_health_insurance_self   BOOLEAN NOT NULL DEFAULT FALSE,
    has_health_insurance_parents BOOLEAN NOT NULL DEFAULT FALSE,
    parents_above_60            BOOLEAN NOT NULL DEFAULT FALSE,
    has_education_loan          BOOLEAN NOT NULL DEFAULT FALSE,
    education_loan_repayment_year INTEGER NOT NULL DEFAULT 1,
    education_loan_interest     INTEGER NOT NULL DEFAULT 0,
    has_donations               BOOLEAN NOT NULL DEFAULT FALSE,
    donation_amount             INTEGER NOT NULL DEFAULT 0,
    age_group                   TEXT NOT NULL CHECK (age_group IN ('below30', 'age30to45', 'age45to60', 'above60', 'above80')),
    actual_basic_salary         INTEGER CHECK (actual_basic_salary IS NULL OR actual_basic_salary >= 0),
    actual_hra_received         INTEGER CHECK (actual_hra_received IS NULL OR actual_hra_received >= 0),
    actual_professional_tax     INTEGER CHECK (actual_professional_tax IS NULL OR actual_professional_tax >= 0),
    health_insurance_self_premium INTEGER CHECK (health_insurance_self_premium IS NULL OR health_insurance_self_premium >= 0),
    health_insurance_parents_premium INTEGER CHECK (health_insurance_parents_premium IS NULL OR health_insurance_parents_premium >= 0),
    savings_interest            INTEGER CHECK (savings_interest IS NULL OR savings_interest >= 0),
    fd_interest                 INTEGER CHECK (fd_interest IS NULL OR fd_interest >= 0),
    employer_nps_contribution   INTEGER CHECK (employer_nps_contribution IS NULL OR employer_nps_contribution >= 0),
    donation_deduction_rate_percent INTEGER CHECK (donation_deduction_rate_percent IS NULL OR donation_deduction_rate_percent BETWEEN 0 AND 100),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, fy)
);

CREATE TABLE IF NOT EXISTS tax_results (
    user_id                     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                          VARCHAR(7) NOT NULL,
    payload                     JSONB NOT NULL,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, fy)
);

CREATE TABLE IF NOT EXISTS done_gaps (
    user_id                     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                          VARCHAR(7) NOT NULL,
    gap_id                      TEXT NOT NULL,
    done_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, fy, gap_id)
);

CREATE TABLE IF NOT EXISTS user_events (
    id                          BIGSERIAL PRIMARY KEY,
    user_id                     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    name                        TEXT NOT NULL,
    metadata                    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS tax_documents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    fy                  VARCHAR(7) NOT NULL,
    document_type       TEXT NOT NULL,
    original_filename   TEXT NOT NULL,
    mime_type           TEXT NOT NULL,
    byte_size           INTEGER NOT NULL CHECK (byte_size > 0),
    sha256_fingerprint  TEXT NOT NULL,
    ciphertext          TEXT NOT NULL,
    iv                  TEXT NOT NULL,
    auth_tag            TEXT NOT NULL,
    parse_status        TEXT NOT NULL DEFAULT 'metadata_ready',
    parse_summary       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_refresh_sessions_user_id
    ON auth_refresh_sessions(user_id);

CREATE INDEX IF NOT EXISTS idx_done_gaps_user_fy
    ON done_gaps(user_id, fy);

CREATE INDEX IF NOT EXISTS idx_user_events_user_created
    ON user_events(user_id, created_at desc);

CREATE INDEX IF NOT EXISTS idx_tax_documents_user_fy
    ON tax_documents(user_id, fy, created_at desc);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_documents_user_fy_type_hash
    ON tax_documents(user_id, fy, document_type, sha256_fingerprint);
