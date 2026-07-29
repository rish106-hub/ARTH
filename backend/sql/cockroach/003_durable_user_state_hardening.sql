ALTER TABLE user_state
  ADD CONSTRAINT user_state_namespace_length CHECK (length(namespace) <= 64);
