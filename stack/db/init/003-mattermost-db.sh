#!/bin/bash
set -e

# Create mattermost database and user
# This runs only on first init (fresh postgres data volume)
# The mattermost database is used by Mattermost (msg.districtsolutions.ai)

MM_USER="${MM_DB_USER:-mattermost}"
MM_PASS="${MM_DB_PASSWORD:-mattermost}"

# Create user first
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER ${MM_USER} WITH PASSWORD '${MM_PASS}';
EOSQL

# CREATE DATABASE cannot run inside a transaction — use -c for single-command mode
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -c "CREATE DATABASE mattermost OWNER ${MM_USER};"

# Grant schema permissions
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "mattermost" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${MM_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${MM_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${MM_USER};
EOSQL
