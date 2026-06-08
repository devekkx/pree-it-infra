#!/bin/bash
set -e

# Read service passwords from mounted secrets
AUTH_DB_PASS=$(cat /run/secrets/postgres_password)
USER_DB_PASS=$(cat /run/secrets/user_db_password)
CHAT_DB_PASS=$(cat /run/secrets/chat_db_password)

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auth_service') THEN
            CREATE ROLE auth_service WITH LOGIN PASSWORD '${AUTH_DB_PASS}';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'user_service') THEN
            CREATE ROLE user_service WITH LOGIN PASSWORD '${USER_DB_PASS}';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'chat_service') THEN
            CREATE ROLE chat_service WITH LOGIN PASSWORD '${CHAT_DB_PASS}';
        END IF;
    END
    \$\$;

    -- Auth service
    GRANT CREATE ON DATABASE ${POSTGRES_DB} TO auth_service;

    -- User service
    GRANT CREATE ON DATABASE ${POSTGRES_DB} TO user_service;

    -- Chat service
    GRANT CREATE ON DATABASE ${POSTGRES_DB} TO chat_service;
EOSQL