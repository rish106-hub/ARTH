ALTER TABLE user_state
  ADD CONSTRAINT user_state_namespace_length CHECK (length(namespace) <= 64);

ALTER TABLE user_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_state FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_user_state_isolation ON user_state;
CREATE POLICY app_user_state_isolation ON user_state
  USING (
    user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID
  )
  WITH CHECK (
    user_id = nullif(split_part(current_setting('application_name'), '.', 2), '')::UUID
  );

REVOKE ALL ON TABLE user_state FROM PUBLIC;
