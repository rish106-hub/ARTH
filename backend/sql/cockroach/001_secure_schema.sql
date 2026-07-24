CREATE ROLE IF NOT EXISTS arth_auth_runtime;
CREATE ROLE IF NOT EXISTS arth_app_runtime;
CREATE ROLE IF NOT EXISTS arth_readonly_ops;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS privacy;
CREATE SCHEMA IF NOT EXISTS profile;
CREATE SCHEMA IF NOT EXISTS vault;
CREATE SCHEMA IF NOT EXISTS payroll;
CREATE SCHEMA IF NOT EXISTS finance;
CREATE SCHEMA IF NOT EXISTS tax;
CREATE SCHEMA IF NOT EXISTS goals;
CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE auth.users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email_lookup        BYTES NOT NULL UNIQUE,
    phone_lookup        BYTES UNIQUE,
    password_hash       STRING,
    password_algorithm  STRING,
    auth_provider       STRING NOT NULL DEFAULT 'password',
    email_verified      BOOL NOT NULL DEFAULT false,
    token_version       INT8 NOT NULL DEFAULT 1,
    status              STRING NOT NULL DEFAULT 'active',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at        TIMESTAMPTZ,
    CONSTRAINT users_status_check CHECK (status IN ('active', 'locked', 'deleting', 'deleted')),
    CONSTRAINT users_password_check CHECK (
      (auth_provider = 'password' AND password_hash IS NOT NULL)
      OR auth_provider <> 'password'
    )
);

CREATE TABLE auth.auth_identities (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    provider            STRING NOT NULL,
    subject_lookup      BYTES NOT NULL,
    payload_ciphertext  BYTES,
    payload_nonce       BYTES,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (provider, subject_lookup),
    UNIQUE (user_id, provider)
);

CREATE TABLE auth.auth_sessions (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    token_hash          BYTES NOT NULL UNIQUE,
    token_family        UUID NOT NULL DEFAULT gen_random_uuid(),
    parent_session_id   UUID,
    user_agent_hash     BYTES,
    ip_prefix_hash      BYTES,
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ,
    reuse_detected_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, parent_session_id)
      REFERENCES auth.auth_sessions(user_id, id) ON DELETE CASCADE
);

CREATE TABLE auth.devices (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    device_lookup       BYTES NOT NULL,
    push_token_ciphertext BYTES,
    push_token_nonce    BYTES,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    status              STRING NOT NULL DEFAULT 'active',
    last_seen_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, device_lookup),
    CONSTRAINT devices_status_check CHECK (status IN ('active', 'revoked'))
);

CREATE TABLE auth.user_keyrings (
    user_id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    wrapped_data_key    BYTES NOT NULL,
    kms_key_name        STRING NOT NULL,
    kms_key_version     STRING,
    key_version         INT8 NOT NULL DEFAULT 1,
    status              STRING NOT NULL DEFAULT 'active',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    rotated_at          TIMESTAMPTZ,
    destroyed_at        TIMESTAMPTZ,
    CONSTRAINT keyrings_status_check CHECK (status IN ('active', 'rotating', 'destroyed'))
);

CREATE TABLE privacy.consents (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    consent_type        STRING NOT NULL,
    policy_version      STRING NOT NULL,
    granted             BOOL NOT NULL,
    source              STRING NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id)
);

CREATE TABLE privacy.data_export_jobs (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    status              STRING NOT NULL DEFAULT 'queued',
    object_key_ciphertext BYTES,
    object_key_nonce    BYTES,
    wrapped_object_key  BYTES,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,
    PRIMARY KEY (user_id, id),
    CONSTRAINT export_status_check CHECK (status IN ('queued', 'running', 'complete', 'failed', 'expired'))
);

CREATE TABLE privacy.deletion_jobs (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    status              STRING NOT NULL DEFAULT 'queued',
    key_destroyed_at    TIMESTAMPTZ,
    database_deleted_at TIMESTAMPTZ,
    objects_deleted_at  TIMESTAMPTZ,
    backup_expires_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,
    PRIMARY KEY (user_id, id),
    CONSTRAINT deletion_status_check CHECK (
      status IN ('queued', 'key_destroyed', 'deleting', 'complete', 'failed')
    )
);

CREATE TABLE privacy.security_tombstones (
    deletion_id         UUID PRIMARY KEY,
    anonymous_subject_hash BYTES NOT NULL UNIQUE,
    deleted_at          TIMESTAMPTZ NOT NULL,
    backup_expires_at   TIMESTAMPTZ NOT NULL
);

CREATE TABLE profile.user_profiles (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id)
);

CREATE TABLE profile.user_preferences (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id)
);

CREATE TABLE profile.employment_periods (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    start_date          DATE NOT NULL,
    end_date            DATE,
    status              STRING NOT NULL DEFAULT 'active',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    CONSTRAINT employment_dates_check CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT employment_status_check CHECK (status IN ('planned', 'active', 'ended'))
);

CREATE TABLE profile.compensation_packages (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    employment_id       UUID NOT NULL,
    effective_from      DATE NOT NULL,
    effective_to        DATE,
    currency            STRING NOT NULL DEFAULT 'INR',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, employment_id)
      REFERENCES profile.employment_periods(user_id, id) ON DELETE CASCADE,
    CONSTRAINT compensation_dates_check CHECK (
      effective_to IS NULL OR effective_to >= effective_from
    )
);

CREATE TABLE profile.compensation_components (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    package_id          UUID NOT NULL,
    component_fingerprint BYTES NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, package_id)
      REFERENCES profile.compensation_packages(user_id, id) ON DELETE CASCADE,
    UNIQUE (user_id, package_id, component_fingerprint)
);

CREATE TABLE vault.documents (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    financial_year      STRING,
    document_type       STRING NOT NULL,
    content_fingerprint BYTES NOT NULL,
    status              STRING NOT NULL DEFAULT 'uploaded',
    review_status       STRING NOT NULL DEFAULT 'not_reviewed',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_at         TIMESTAMPTZ,
    deleted_at          TIMESTAMPTZ,
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, content_fingerprint),
    CONSTRAINT document_status_check CHECK (
      status IN ('uploaded', 'processing', 'ready', 'failed', 'archived', 'deleting')
    ),
    CONSTRAINT document_review_check CHECK (
      review_status IN ('not_reviewed', 'needs_review', 'confirmed')
    )
);

CREATE TABLE vault.document_objects (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID NOT NULL,
    object_generation   STRING NOT NULL,
    object_hash         BYTES NOT NULL,
    byte_size           INT8 NOT NULL CHECK (byte_size > 0),
    wrapped_object_key  BYTES NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    status              STRING NOT NULL DEFAULT 'active',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    UNIQUE (user_id, document_id, object_generation),
    CONSTRAINT object_status_check CHECK (status IN ('active', 'deleting', 'deleted'))
);

CREATE TABLE vault.processing_jobs (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID NOT NULL,
    provider            STRING NOT NULL,
    stage               STRING NOT NULL,
    status              STRING NOT NULL DEFAULT 'queued',
    attempt_count       INT8 NOT NULL DEFAULT 0,
    error_code          STRING,
    input_schema_version INT8 NOT NULL,
    output_schema_version INT8,
    queued_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    CONSTRAINT processing_status_check CHECK (
      status IN ('queued', 'running', 'complete', 'failed', 'expired')
    )
);

CREATE TABLE vault.document_extractions (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID NOT NULL,
    job_id              UUID NOT NULL,
    model_name          STRING NOT NULL,
    model_version       STRING,
    prompt_version      STRING,
    confidence_basis_points INT8 CHECK (
      confidence_basis_points IS NULL
      OR confidence_basis_points BETWEEN 0 AND 10000
    ),
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, job_id)
      REFERENCES vault.processing_jobs(user_id, id) ON DELETE CASCADE
);

CREATE TABLE vault.extracted_facts (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID NOT NULL,
    extraction_id       UUID NOT NULL,
    fact_fingerprint    BYTES NOT NULL,
    confidence_basis_points INT8 CHECK (
      confidence_basis_points IS NULL
      OR confidence_basis_points BETWEEN 0 AND 10000
    ),
    source_page         INT8,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    superseded_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, extraction_id)
      REFERENCES vault.document_extractions(user_id, id) ON DELETE CASCADE
);

CREATE TABLE vault.document_events (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID,
    event_type          STRING NOT NULL,
    payload_ciphertext  BYTES,
    payload_nonce       BYTES,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE
);

CREATE TABLE reference.payroll_components (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stable_code         STRING NOT NULL UNIQUE,
    item_kind           STRING NOT NULL,
    broad_category      STRING NOT NULL,
    subcategory         STRING NOT NULL,
    display_name        STRING NOT NULL,
    active              BOOL NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT payroll_component_kind_check CHECK (item_kind IN ('earning', 'deduction'))
);

CREATE TABLE payroll.component_aliases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    component_id        UUID NOT NULL REFERENCES reference.payroll_components(id),
    normalized_alias    STRING NOT NULL,
    locale              STRING NOT NULL DEFAULT 'en-IN',
    source              STRING NOT NULL DEFAULT 'system',
    approved            BOOL NOT NULL DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (normalized_alias, locale)
);

CREATE TABLE payroll.statements (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    document_id         UUID,
    period_start        DATE NOT NULL,
    period_end          DATE NOT NULL,
    currency            STRING NOT NULL DEFAULT 'INR',
    status              STRING NOT NULL DEFAULT 'extracted',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    CONSTRAINT statement_period_check CHECK (period_end >= period_start),
    CONSTRAINT statement_status_check CHECK (status IN ('extracted', 'needs_review', 'confirmed'))
);

CREATE TABLE payroll.line_items (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    statement_id        UUID NOT NULL,
    item_kind           STRING NOT NULL,
    component_fingerprint BYTES NOT NULL,
    source_label_fingerprint BYTES NOT NULL,
    classification_source STRING NOT NULL,
    confidence_basis_points INT8 CHECK (
      confidence_basis_points IS NULL
      OR confidence_basis_points BETWEEN 0 AND 10000
    ),
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    supersedes_item_id  UUID,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, statement_id)
      REFERENCES payroll.statements(user_id, id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, supersedes_item_id)
      REFERENCES payroll.line_items(user_id, id),
    UNIQUE (
      user_id,
      statement_id,
      item_kind,
      component_fingerprint,
      source_label_fingerprint
    ),
    CONSTRAINT line_item_kind_check CHECK (item_kind IN ('earning', 'deduction')),
    CONSTRAINT classification_source_check CHECK (
      classification_source IN ('gemini', 'rule', 'user')
    )
);

CREATE TABLE reference.financial_categories (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stable_code         STRING NOT NULL UNIQUE,
    parent_id           UUID REFERENCES reference.financial_categories(id),
    display_name        STRING NOT NULL,
    category_type       STRING NOT NULL,
    active              BOOL NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE finance.transactions (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    source_fingerprint  BYTES NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL,
    category_fingerprint BYTES,
    classification_source STRING,
    confidence_basis_points INT8 CHECK (
      confidence_basis_points IS NULL
      OR confidence_basis_points BETWEEN 0 AND 10000
    ),
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, source_fingerprint)
);

CREATE TABLE finance.transaction_corrections (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    transaction_id      UUID NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, transaction_id)
      REFERENCES finance.transactions(user_id, id) ON DELETE CASCADE
);

CREATE TABLE finance.spend_snapshots (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    window_start        DATE NOT NULL,
    window_end          DATE NOT NULL,
    input_revision      INT8 NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, window_start, window_end, input_revision),
    CONSTRAINT snapshot_window_check CHECK (window_end >= window_start)
);

CREATE TABLE tax.tax_years (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    financial_year      STRING NOT NULL UNIQUE,
    assessment_year     STRING NOT NULL UNIQUE,
    starts_on           DATE NOT NULL,
    ends_on             DATE NOT NULL,
    status              STRING NOT NULL DEFAULT 'draft',
    CONSTRAINT tax_year_dates_check CHECK (ends_on >= starts_on),
    CONSTRAINT tax_year_status_check CHECK (status IN ('draft', 'active', 'closed'))
);

CREATE TABLE tax.rule_versions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tax_year_id         UUID NOT NULL REFERENCES tax.tax_years(id),
    engine_version      STRING NOT NULL,
    rule_hash           BYTES NOT NULL,
    effective_at        TIMESTAMPTZ NOT NULL,
    retired_at          TIMESTAMPTZ,
    UNIQUE (tax_year_id, engine_version)
);

CREATE TABLE tax.tax_facts (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    tax_year_id         UUID NOT NULL REFERENCES tax.tax_years(id),
    source_document_id  UUID,
    fact_fingerprint    BYTES NOT NULL,
    effective_from      DATE,
    effective_to        DATE,
    confidence_basis_points INT8 CHECK (
      confidence_basis_points IS NULL
      OR confidence_basis_points BETWEEN 0 AND 10000
    ),
    source              STRING NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, source_document_id)
      REFERENCES vault.documents(user_id, id) ON DELETE CASCADE,
    UNIQUE (user_id, tax_year_id, fact_fingerprint, effective_from),
    CONSTRAINT tax_fact_dates_check CHECK (
      effective_to IS NULL OR effective_from IS NULL OR effective_to >= effective_from
    )
);

CREATE TABLE tax.tax_computations (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    tax_year_id         UUID NOT NULL REFERENCES tax.tax_years(id),
    rule_version_id     UUID NOT NULL REFERENCES tax.rule_versions(id),
    input_hash          BYTES NOT NULL,
    status              STRING NOT NULL DEFAULT 'complete',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, tax_year_id, rule_version_id, input_hash),
    CONSTRAINT computation_status_check CHECK (status IN ('complete', 'superseded', 'failed'))
);

CREATE TABLE tax.readiness_items (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    tax_year_id         UUID NOT NULL REFERENCES tax.tax_years(id),
    item_fingerprint    BYTES NOT NULL,
    status              STRING NOT NULL DEFAULT 'open',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, tax_year_id, item_fingerprint),
    CONSTRAINT readiness_status_check CHECK (status IN ('open', 'done', 'dismissed'))
);

CREATE TABLE goals.goals (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    start_date          DATE NOT NULL,
    target_date         DATE NOT NULL,
    status              STRING NOT NULL DEFAULT 'active',
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    version             INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    CONSTRAINT goal_dates_check CHECK (target_date >= start_date),
    CONSTRAINT goal_status_check CHECK (status IN ('active', 'paused', 'complete', 'cancelled'))
);

CREATE TABLE goals.goal_plans (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    goal_id             UUID NOT NULL,
    input_revision      INT8 NOT NULL,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, goal_id)
      REFERENCES goals.goals(user_id, id) ON DELETE CASCADE,
    UNIQUE (user_id, goal_id, input_revision)
);

CREATE TABLE goals.goal_contributions (
    user_id             UUID NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    goal_id             UUID NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL,
    source_fingerprint  BYTES,
    payload_ciphertext  BYTES NOT NULL,
    payload_nonce       BYTES NOT NULL,
    key_version         INT8 NOT NULL DEFAULT 1,
    schema_version      INT8 NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    FOREIGN KEY (user_id, goal_id)
      REFERENCES goals.goals(user_id, id) ON DELETE CASCADE,
    UNIQUE (user_id, goal_id, source_fingerprint)
);

CREATE TABLE reference.employers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    normalized_name     STRING NOT NULL UNIQUE,
    display_name        STRING NOT NULL,
    source              STRING NOT NULL,
    approved            BOOL NOT NULL DEFAULT false,
    usage_count         INT8 NOT NULL DEFAULT 0,
    submitted_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ops.idempotency_keys (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    idempotency_key     STRING NOT NULL,
    request_hash        BYTES NOT NULL,
    response_status     INT8,
    response_ciphertext BYTES,
    response_nonce      BYTES,
    key_version         INT8 NOT NULL DEFAULT 1,
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, idempotency_key)
);

CREATE TABLE ops.sync_revisions (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    revision            INT8 NOT NULL DEFAULT unique_rowid(),
    entity_type         STRING NOT NULL,
    entity_id           UUID NOT NULL,
    operation           STRING NOT NULL,
    entity_version      INT8 NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, revision),
    CONSTRAINT sync_operation_check CHECK (operation IN ('upsert', 'delete'))
);

CREATE TABLE ops.outbox_events (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    event_type          STRING NOT NULL,
    aggregate_id        UUID NOT NULL,
    payload_ciphertext  BYTES,
    payload_nonce       BYTES,
    key_version         INT8 NOT NULL DEFAULT 1,
    available_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    attempt_count       INT8 NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id)
);

CREATE TABLE ops.audit_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type          STRING NOT NULL,
    outcome             STRING NOT NULL,
    actor_type          STRING NOT NULL,
    correlation_id      UUID,
    subject_hash        BYTES,
    metadata            JSONB NOT NULL DEFAULT '{}'::JSONB,
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '90 days'
);

CREATE INDEX auth_sessions_user_active_idx
    ON auth.auth_sessions (user_id, expires_at DESC)
    WHERE revoked_at IS NULL;
CREATE INDEX employment_user_dates_idx
    ON profile.employment_periods (user_id, start_date DESC);
CREATE INDEX documents_user_status_idx
    ON vault.documents (user_id, status, updated_at DESC);
CREATE INDEX jobs_user_document_idx
    ON vault.processing_jobs (user_id, document_id, queued_at DESC);
CREATE INDEX statements_user_period_idx
    ON payroll.statements (user_id, period_end DESC);
CREATE INDEX transactions_user_date_idx
    ON finance.transactions (user_id, occurred_at DESC);
CREATE INDEX tax_facts_user_year_idx
    ON tax.tax_facts (user_id, tax_year_id, updated_at DESC);
CREATE INDEX goals_user_status_idx
    ON goals.goals (user_id, status, target_date);
CREATE INDEX sync_user_revision_idx
    ON ops.sync_revisions (user_id, revision);
CREATE INDEX outbox_available_idx
    ON ops.outbox_events (available_at)
    WHERE completed_at IS NULL;
CREATE INDEX audit_expiry_idx ON ops.audit_events (expires_at);

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.users FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_runtime_users ON auth.users
    FOR ALL TO arth_auth_runtime USING (true) WITH CHECK (true);
CREATE POLICY app_runtime_users ON auth.users
    FOR ALL TO arth_app_runtime
    USING (id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE auth.auth_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.auth_identities FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_runtime_identities ON auth.auth_identities
    FOR ALL TO arth_auth_runtime USING (true) WITH CHECK (true);
CREATE POLICY app_user_isolation ON auth.auth_identities
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE auth.auth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.auth_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY auth_runtime_sessions ON auth.auth_sessions
    FOR ALL TO arth_auth_runtime USING (true) WITH CHECK (true);
CREATE POLICY app_user_isolation ON auth.auth_sessions
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE auth.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.devices FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON auth.devices
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE auth.user_keyrings ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.user_keyrings FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON auth.user_keyrings
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE privacy.consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.consents FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON privacy.consents
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE privacy.data_export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.data_export_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON privacy.data_export_jobs
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE privacy.deletion_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON privacy.deletion_jobs
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE profile.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile.user_profiles FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON profile.user_profiles
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE profile.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile.user_preferences FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON profile.user_preferences
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE profile.employment_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile.employment_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON profile.employment_periods
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE profile.compensation_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile.compensation_packages FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON profile.compensation_packages
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE profile.compensation_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile.compensation_components FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON profile.compensation_components
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.documents FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.documents
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.document_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.document_objects FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.document_objects
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.processing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.processing_jobs FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.processing_jobs
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.document_extractions ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.document_extractions FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.document_extractions
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.extracted_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.extracted_facts FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.extracted_facts
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE vault.document_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault.document_events FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON vault.document_events
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE payroll.statements ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll.statements FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON payroll.statements
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE payroll.line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll.line_items FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON payroll.line_items
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE finance.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.transactions FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON finance.transactions
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE finance.transaction_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.transaction_corrections FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON finance.transaction_corrections
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE finance.spend_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.spend_snapshots FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON finance.spend_snapshots
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE tax.tax_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax.tax_facts FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON tax.tax_facts
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE tax.tax_computations ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax.tax_computations FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON tax.tax_computations
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE tax.readiness_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax.readiness_items FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON tax.readiness_items
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE goals.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals.goals FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON goals.goals
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE goals.goal_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals.goal_plans FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON goals.goal_plans
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE goals.goal_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE goals.goal_contributions FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON goals.goal_contributions
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE ops.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.idempotency_keys FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON ops.idempotency_keys
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE ops.sync_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.sync_revisions FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON ops.sync_revisions
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

ALTER TABLE ops.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_events FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON ops.outbox_events
    FOR ALL TO arth_app_runtime
    USING (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID)
    WITH CHECK (user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID);

GRANT USAGE ON SCHEMA auth TO arth_auth_runtime, arth_app_runtime;
GRANT USAGE ON SCHEMA privacy, profile, vault, payroll, finance, tax, goals, reference, ops
    TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.users, auth.auth_identities, auth.auth_sessions
    TO arth_auth_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA auth TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA privacy TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA profile TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA vault TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA payroll TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA finance TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA tax TO arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA goals TO arth_app_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA reference TO arth_auth_runtime, arth_app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ops.idempotency_keys, ops.sync_revisions, ops.outbox_events
    TO arth_app_runtime;
GRANT USAGE ON SCHEMA ops TO arth_readonly_ops;
GRANT SELECT ON ops.audit_events, ops.schema_migrations TO arth_readonly_ops;
