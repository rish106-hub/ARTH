CREATE TABLE IF NOT EXISTS security_tombstones (
    deletion_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    anonymous_subject_hash  TEXT NOT NULL UNIQUE,
    deleted_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    backup_expires_at       TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_security_tombstones_backup_expiry
    ON security_tombstones(backup_expires_at);
