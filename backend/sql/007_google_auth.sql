ALTER TABLE app_users
    ALTER COLUMN password_hash DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS google_subject TEXT,
    ADD COLUMN IF NOT EXISTS auth_provider TEXT NOT NULL DEFAULT 'password';

CREATE UNIQUE INDEX IF NOT EXISTS uidx_app_users_google_subject
    ON app_users(google_subject)
    WHERE google_subject IS NOT NULL;
