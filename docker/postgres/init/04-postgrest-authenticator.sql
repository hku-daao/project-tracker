-- PostgREST login role (switches to anon / authenticated). Password set in step4 script for existing DBs.
-- Fresh installs: run scripts/step4_setup_postgrest.sh after first postgres start.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'postgrest-authenticator-dev-change-me';
  END IF;
END $$;

GRANT CONNECT ON DATABASE project_tracker TO authenticator;
GRANT USAGE ON SCHEMA public TO authenticator;
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
