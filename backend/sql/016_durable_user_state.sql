CREATE TABLE IF NOT EXISTS user_state (
    user_id             UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    namespace           TEXT NOT NULL CHECK (length(namespace) <= 64),
    payload_ciphertext  TEXT,
    payload_iv          TEXT,
    payload_auth_tag    TEXT,
    deleted             BOOLEAN NOT NULL DEFAULT FALSE,
    client_updated_at   TIMESTAMPTZ NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, namespace),
    CHECK (
      (deleted = TRUE
        AND payload_ciphertext IS NULL
        AND payload_iv IS NULL
        AND payload_auth_tag IS NULL)
      OR
      (deleted = FALSE
        AND payload_ciphertext IS NOT NULL
        AND payload_iv IS NOT NULL
        AND payload_auth_tag IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_user_state_updated
    ON user_state(user_id, updated_at DESC);

ALTER TABLE user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_state FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_user_state_isolation ON user_state;
CREATE POLICY app_user_state_isolation ON user_state
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

REVOKE ALL ON TABLE user_state FROM PUBLIC;
