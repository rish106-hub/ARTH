-- Tenant row-level security for the flat schema.
-- Works on Postgres and on CockroachDB when DB_DIALECT=postgres (compatibility mode).
-- Policies read the authenticated user id from application_name (set per request
-- via set_config) and allow background jobs through arth.system=true.

CREATE OR REPLACE FUNCTION arth_request_user_id() RETURNS uuid AS $$
  SELECT nullif(split_part(current_setting('application_name', true), '.', 2), '')::uuid;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION arth_is_system_request() RETURNS boolean AS $$
  SELECT coalesce(nullif(current_setting('arth.system', true), ''), 'false') = 'true';
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION arth_tenant_visible(target_user_id uuid) RETURNS boolean AS $$
  SELECT arth_is_system_request() OR target_user_id = arth_request_user_id();
$$ LANGUAGE sql STABLE;

ALTER TABLE tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_profiles FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON tax_profiles;
CREATE POLICY tenant_isolation ON tax_profiles
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE tax_profiles FROM PUBLIC;

ALTER TABLE tax_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_results FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON tax_results;
CREATE POLICY tenant_isolation ON tax_results
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE tax_results FROM PUBLIC;

ALTER TABLE done_gaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE done_gaps FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON done_gaps;
CREATE POLICY tenant_isolation ON done_gaps
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE done_gaps FROM PUBLIC;

ALTER TABLE user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON user_events;
CREATE POLICY tenant_isolation ON user_events
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE user_events FROM PUBLIC;

ALTER TABLE tax_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_documents FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON tax_documents;
CREATE POLICY tenant_isolation ON tax_documents
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE tax_documents FROM PUBLIC;

ALTER TABLE user_private_identity ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_private_identity FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON user_private_identity;
CREATE POLICY tenant_isolation ON user_private_identity
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE user_private_identity FROM PUBLIC;

ALTER TABLE money_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE money_goals FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON money_goals;
CREATE POLICY tenant_isolation ON money_goals
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE money_goals FROM PUBLIC;

ALTER TABLE spend_maps ENABLE ROW LEVEL SECURITY;
ALTER TABLE spend_maps FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON spend_maps;
CREATE POLICY tenant_isolation ON spend_maps
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE spend_maps FROM PUBLIC;

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON device_tokens;
CREATE POLICY tenant_isolation ON device_tokens
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE device_tokens FROM PUBLIC;

ALTER TABLE push_delivery_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_delivery_claims FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON push_delivery_claims;
CREATE POLICY tenant_isolation ON push_delivery_claims
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE push_delivery_claims FROM PUBLIC;

ALTER TABLE document_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_events FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON document_events;
CREATE POLICY tenant_isolation ON document_events
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
REVOKE ALL ON TABLE document_events FROM PUBLIC;

DROP POLICY IF EXISTS app_user_state_isolation ON user_state;
CREATE POLICY app_user_state_isolation ON user_state
  USING (arth_tenant_visible(user_id))
  WITH CHECK (arth_tenant_visible(user_id));
