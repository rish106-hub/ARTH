CREATE UNIQUE INDEX IF NOT EXISTS uidx_user_private_identity_active_pan_fingerprint
    ON user_private_identity(pan_fingerprint)
    WHERE pan_fingerprint IS NOT NULL;
