#!/bin/bash
# Create the SOC agent database
# This runs on first Postgres container init alongside 001-schema.sql
# The socagent database is used by the AI-SOC platform (aisoc.districtsolutions.ai)
# Uses env vars: SOC_DB_USER, SOC_DB_PASSWORD (set in db.yaml from env.sh)

set -e

SOC_USER="${SOC_DB_USER:-socagent}"
SOC_PASS="${SOC_DB_PASSWORD:-socagent}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE socagent;
    CREATE USER ${SOC_USER} WITH PASSWORD '${SOC_PASS}';
    GRANT ALL PRIVILEGES ON DATABASE socagent TO ${SOC_USER};
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "socagent" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${SOC_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${SOC_USER};
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${SOC_USER};

    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    CREATE TABLE IF NOT EXISTS alerts (
        id VARCHAR(64) PRIMARY KEY,
        source VARCHAR(32),
        raw_data JSONB,
        asset_id VARCHAR(64),
        severity VARCHAR(32),
        status VARCHAR(32) DEFAULT 'new',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX idx_alerts_status ON alerts (status);
    CREATE INDEX idx_alerts_severity ON alerts (severity);
    CREATE INDEX idx_alerts_source ON alerts (source);
    CREATE INDEX idx_alerts_created_at ON alerts (created_at);
    CREATE INDEX idx_alerts_status_severity ON alerts (status, severity);

    CREATE TABLE IF NOT EXISTS investigations (
        id VARCHAR(64) PRIMARY KEY,
        alert_id VARCHAR(64),
        asset_id VARCHAR(64),
        triage_findings TEXT,
        vuln_findings TEXT,
        hunt_findings TEXT,
        final_verdict TEXT,
        severity VARCHAR(32),
        recommended_action TEXT,
        agent_trace JSONB,
        hitl_required BOOLEAN DEFAULT FALSE,
        hitl_status VARCHAR(32),
        hitl_thread_id VARCHAR(128),
        analyst_notes TEXT,
        analyst_severity_override VARCHAR(32),
        resolved_at TIMESTAMPTZ,
        resolved_by VARCHAR(128),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX idx_investigations_hitl_status ON investigations (hitl_status);
    CREATE INDEX idx_investigations_severity ON investigations (severity);
    CREATE INDEX idx_investigations_created_at ON investigations (created_at);
    CREATE INDEX idx_investigations_alert_id ON investigations (alert_id);

    CREATE TABLE IF NOT EXISTS assets (
        id VARCHAR(64) PRIMARY KEY,
        hostname VARCHAR(256),
        ec2_instance_id VARCHAR(64),
        ip_address VARCHAR(64),
        wiz_resource_id VARCHAR(256),
        qualys_asset_id VARCHAR(64),
        snyk_project_id VARCHAR(256),
        criticality VARCHAR(32) DEFAULT 'medium',
        owner VARCHAR(128),
        environment VARCHAR(64),
        tags JSONB DEFAULT '{}'::jsonb,
        fp_patterns JSONB DEFAULT '[]'::jsonb,
        last_investigation TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX idx_assets_hostname ON assets (hostname);
    CREATE INDEX idx_assets_ec2_instance_id ON assets (ec2_instance_id);
    CREATE INDEX idx_assets_environment ON assets (environment);
    CREATE INDEX idx_assets_criticality ON assets (criticality);

    CREATE TABLE IF NOT EXISTS analyst_feedback (
        id VARCHAR(64) PRIMARY KEY,
        investigation_id VARCHAR(64),
        alert_id VARCHAR(64),
        asset_id VARCHAR(64),
        agent_severity VARCHAR(32),
        analyst_severity VARCHAR(32),
        action VARCHAR(32),
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX idx_analyst_feedback_investigation ON analyst_feedback (investigation_id);
    CREATE INDEX idx_analyst_feedback_action ON analyst_feedback (action);
EOSQL
