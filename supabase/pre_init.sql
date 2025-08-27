-- Pre-init SQL: defensive creations to help migrations run on partially-populated DBs
CREATE SCHEMA IF NOT EXISTS auth;

-- Create factor_type enum if it doesn't already exist (best-effort local dev)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON t.typnamespace = n.oid
        WHERE t.typname = 'factor_type' AND n.nspname = 'auth'
    ) THEN
        CREATE TYPE auth.factor_type AS ENUM ('email','phone','totp','recovery');
    END IF;
END$$;
