CREATE TABLE IF NOT EXISTS user_state (
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    namespace           STRING NOT NULL,
    payload_ciphertext  STRING,
    payload_iv          STRING,
    payload_auth_tag    STRING,
    deleted             BOOL NOT NULL DEFAULT false,
    client_updated_at   TIMESTAMPTZ NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, namespace),
    CONSTRAINT user_state_payload_check CHECK (
      (deleted = true
        AND payload_ciphertext IS NULL
        AND payload_iv IS NULL
        AND payload_auth_tag IS NULL)
      OR
      (deleted = false
        AND payload_ciphertext IS NOT NULL
        AND payload_iv IS NOT NULL
        AND payload_auth_tag IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_user_state_updated
    ON user_state(user_id, updated_at DESC);

ALTER TABLE user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_state FORCE ROW LEVEL SECURITY;
CREATE POLICY app_user_isolation ON user_state
    FOR ALL TO arth_app_runtime
    USING (
      user_id = nullif(
        split_part(current_setting('application_name'), '.', 2),
        ''
      )::UUID
    )
    WITH CHECK (
      user_id = nullif(
        split_part(current_setting('application_name'), '.', 2),
        ''
      )::UUID
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE user_state TO arth_app_runtime;
