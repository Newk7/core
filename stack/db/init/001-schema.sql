-- Task tracking schema for biz-tool pipeline
-- Tasks are identified by UUID, with manifest.json published to S3
-- Messages flow through SQS queues for async processing

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    task_type VARCHAR(128) NOT NULL,
    payload JSONB,
    s3_manifest_key TEXT,
    sqs_message_id VARCHAR(256),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_tasks_status ON tasks (status);
CREATE INDEX idx_tasks_task_type ON tasks (task_type);
CREATE INDEX idx_tasks_created_at ON tasks (created_at);
CREATE INDEX idx_tasks_status_type ON tasks (status, task_type);

CREATE TABLE IF NOT EXISTS task_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    s3_result_key TEXT,
    result_data JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_task_results_task_id ON task_results (task_id);
