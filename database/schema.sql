-- ============================================================
-- ARTH Tax Gap Intelligence — SQL Schema
-- FY 2025-26 / AY 2026-27
--
-- This is the canonical relational equivalent of the Firestore
-- document schema used in production.
--
-- Production backend: Firebase Firestore (Spark free tier)
--   Collection path map:
--     users/{uid}                         → table: users
--     users/{uid}/tax_profiles/{fy}       → table: tax_profiles
--     users/{uid}/tax_results/{fy}        → table: tax_results
--     users/{uid}/done_gaps/{key}         → table: done_gaps
--
-- Use this schema if you migrate to PostgreSQL (e.g. Neon, Railway).
-- ============================================================

-- Extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Users ────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    uid                 VARCHAR(128)    PRIMARY KEY,    -- Firebase UID
    name                VARCHAR(100)    NOT NULL,
    pan_masked          CHAR(10)        NOT NULL,       -- e.g. AXXXX9999A
    email               VARCHAR(255),                   -- null for manual accounts
    auth_method         VARCHAR(10)     NOT NULL DEFAULT 'manual'
                                        CHECK (auth_method IN ('manual', 'google')),
    biometrics_enabled  BOOLEAN         NOT NULL DEFAULT FALSE,
    app_version         VARCHAR(20),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    last_seen           TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ── Tax profiles (12 onboarding answers per FY) ──────────────────────────────
CREATE TABLE tax_profiles (
    id                      SERIAL          PRIMARY KEY,
    uid                     VARCHAR(128)    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    fy                      VARCHAR(7)      NOT NULL,   -- '2025-26'

    -- Q01
    annual_ctc              INTEGER         NOT NULL CHECK (annual_ctc >= 0),

    -- Q02
    employment_type         VARCHAR(20)     NOT NULL
                            CHECK (employment_type IN ('salaried', 'selfEmployed')),

    -- Q03
    age_group               VARCHAR(20)     NOT NULL
                            CHECK (age_group IN ('below30','age30to45','age45to60','above60')),

    -- Q04 city
    city                    VARCHAR(100),
    is_metro_city           BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Q05 rent
    pays_rent               BOOLEAN         NOT NULL DEFAULT FALSE,
    monthly_rent            INTEGER         NOT NULL DEFAULT 0 CHECK (monthly_rent >= 0),
    has_hra                 BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Q06 80C
    invested_80c            INTEGER         NOT NULL DEFAULT 0
                            CHECK (invested_80c BETWEEN 0 AND 150000),

    -- Q07 NPS
    nps_extra_contribution  INTEGER         NOT NULL DEFAULT 0
                            CHECK (nps_extra_contribution BETWEEN 0 AND 50000),

    -- Q08 health insurance
    has_health_ins_self     BOOLEAN         NOT NULL DEFAULT FALSE,
    has_health_ins_parents  BOOLEAN         NOT NULL DEFAULT FALSE,
    parents_above_60        BOOLEAN         NOT NULL DEFAULT FALSE,

    -- Q09 home loan
    has_home_loan           BOOLEAN         NOT NULL DEFAULT FALSE,
    home_loan_interest      INTEGER         NOT NULL DEFAULT 0 CHECK (home_loan_interest >= 0),

    -- Q10 education loan
    has_education_loan      BOOLEAN         NOT NULL DEFAULT FALSE,
    education_loan_interest INTEGER         NOT NULL DEFAULT 0 CHECK (education_loan_interest >= 0),
    education_loan_year     INTEGER         NOT NULL DEFAULT 0 CHECK (education_loan_year BETWEEN 0 AND 8),

    -- Q11 donations
    has_donations           BOOLEAN         NOT NULL DEFAULT FALSE,
    donation_amount         INTEGER         NOT NULL DEFAULT 0 CHECK (donation_amount >= 0),

    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (uid, fy)
);

-- ── Tax results (computed gap analysis per FY) ───────────────────────────────
CREATE TABLE tax_results (
    id                  SERIAL              PRIMARY KEY,
    uid                 VARCHAR(128)        NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    fy                  VARCHAR(7)          NOT NULL,

    old_regime_tax      DOUBLE PRECISION    NOT NULL,
    new_regime_tax      DOUBLE PRECISION    NOT NULL,
    old_taxable_income  DOUBLE PRECISION    NOT NULL,
    new_taxable_income  DOUBLE PRECISION    NOT NULL,
    total_deductions    DOUBLE PRECISION    NOT NULL,
    better_regime       VARCHAR(20)         NOT NULL CHECK (better_regime IN ('oldRegime','newRegime')),
    regime_savings      DOUBLE PRECISION    NOT NULL,

    total_gap           INTEGER             NOT NULL,
    gap_count           INTEGER             NOT NULL,
    gaps                JSONB,              -- serialised list of GapCard objects

    computed_at         TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    UNIQUE (uid, fy)
);

-- ── Done gaps (user has actioned a deduction gap) ────────────────────────────
CREATE TABLE done_gaps (
    id          SERIAL          PRIMARY KEY,
    uid         VARCHAR(128)    NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
    gap_id      VARCHAR(50)     NOT NULL,   -- e.g. 'T01_80C_gap'
    fy          VARCHAR(7)      NOT NULL,

    done_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    UNIQUE (uid, gap_id, fy)
);

-- ── Indices ───────────────────────────────────────────────────────────────────
CREATE INDEX idx_tax_profiles_uid ON tax_profiles(uid);
CREATE INDEX idx_tax_results_uid  ON tax_results(uid);
CREATE INDEX idx_done_gaps_uid_fy ON done_gaps(uid, fy);
