# core

Infrastructure and tooling for the BizTool AI platform.

## Architecture

- **Compute**: EC2 host on AWS (Amazon Linux 2023, t3.medium) with Docker and Nginx
- **Data Layer**: S3 (task manifest.json files by UUID) + Postgres (task tracking DB)
- **Message Queue**: AWS SQS (task queue + result queue with DLQs)
- **API**: FastAPI/Uvicorn REST API for frontend apps
- **Workers**: SQS-polling task workers for document processing and shredding
- **UI**: Open WebUI container running behind Nginx reverse proxy

### Task Flow

1. Frontend submits task via REST API (`POST /api/v1/tasks` or `/api/v1/upload`)
2. API creates task in Postgres, publishes to SQS task queue
3. Worker polls SQS, deserializes task, runs handler (shred, chat, etc.)
4. Worker converts documents to markdown via Docling, writes parquet to S3
5. Results uploaded to S3 at `tasks/{uuid}/manifest.json`
6. Completion notification sent to SQS result queue
7. Task status updated in Postgres

## AWS Account

- **Account**: 381492049589
- **Region**: us-east-1
- **VPC**: vpc-0dd28884da7e4d4eb (10.0.0.0/16)
- **Subnet**: subnet-0531a7a14eef69db2 (10.0.0.0/24, us-east-1b, public)
- **IGW**: igw-0ff11a9a0a107c8ed

## Python Core (`core/`)

The `core` Python package contains all custom business logic and pipeline code.

```
core/
  log.py                        # Logger (stdout with color support)
  s3/                           # S3 operations
    get_client.py               # boto3 S3 client factory
    upload_file.py              # Upload with encryption
    download_file.py            # Download to memory
    download_s3_keys.py         # Batch download by S3 URIs
  sqs/                          # SQS message queue (replaces Redis for queuing)
    get_client.py               # boto3 SQS client + queue URL resolver
    publish.py                  # Publish tasks and results to queues
    consume.py                  # Long-poll receive + delete messages
  db/                           # Postgres
    get_db_pool.py              # Connection pool (dev/prod env switching)
  jobs/                         # Task model
    task.py                     # Task class with DB insert/update, S3 manifest, SQS pub
  eng/                          # Engine
    resources.py                # EngResources (shared DB pool, SQS, S3 clients)
    handle_task.py              # Task dispatcher (shred, chat, etc.)
    worker.py                   # SQS polling worker loop with graceful shutdown
  docling/                      # Document conversion
    convert_file_to_markdown.py # Multi-format to markdown (PDF, DOCX, HTML, PPTX, CSV)
                                # OCR support: Tesseract, EasyOCR, RapidOCR, Mac OCR
                                # Bounding box artifact extraction
  shred/                        # Document shredding pipeline
    run_shred.py                # Download from S3, convert to markdown, write parquet
  api/                          # FastAPI REST API
    server.py                   # Endpoints: health, tasks CRUD, file upload
```

### Key Patterns

```python
# Import pattern
from core.log import create_log
from core.jobs.task import Task
from core.eng.resources import EngResources
from core.sqs.publish import publish_task
from core.s3.download_s3_keys import download_s3_keys
from core.docling.convert_file_to_markdown import convert_to_markdown

# Create a task
tk = Task(type='shred', msg='process document', user_id='user1')
tk.insert(db_pool)
publish_task(task_data=tk.to_dict())

# Status codes: -999=init, 0=success, 150-500=processing, <0=error
```

## Stack Layout

```
stack/
  cf/                           # CloudFormation templates
    build-host/
      host.yaml                 # EC2 build host (deployed as AI-BizTool stack)
      example-host.yaml         # Reference Ubuntu host template
    s3/
      s3.yaml                   # Task data S3 bucket
    sqs/
      sqs.yaml                  # Task + result SQS queues with DLQs
    windows-vm/
      ec2.yaml                  # (placeholder)
  api/                          # Core API container
    Dockerfile                  # Python 3.11 + tesseract + poppler
    docker-compose.yaml         # FastAPI on port 8000
  worker/                       # Task worker container
    Dockerfile                  # Same base as API
    docker-compose.yaml         # SQS polling worker
  db/
    db.yaml                     # Docker-compose for Postgres on the host
    init/
      001-schema.sql            # Task tracking schema (tasks + task_results)
  oweb/
    docker-compose.yaml         # Open WebUI container
    nginx.conf                  # Nginx reverse proxy config
  redis/                        # (placeholder)
  vim-files/                    # Dev environment setup scripts (vim, nvm, fzf)
```

## Deploying

### CloudFormation Stacks

```bash
# EC2 host (already deployed)
aws cloudformation deploy \
  --template-file stack/cf/build-host/host.yaml \
  --stack-name AI-BizTool \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# S3 bucket
aws cloudformation deploy \
  --template-file stack/cf/s3/s3.yaml \
  --stack-name biz-tool-s3 \
  --region us-east-1

# SQS queues
aws cloudformation deploy \
  --template-file stack/cf/sqs/sqs.yaml \
  --stack-name biz-tool-sqs \
  --region us-east-1
```

### On the EC2 Host

```bash
# Start Postgres
cd stack/db && docker compose up -d

# Start Open WebUI
cd stack/oweb && docker compose up -d

# Build and start the API
cd stack/api && docker compose up -d --build

# Build and start the worker
cd stack/worker && docker compose up -d --build

# Copy nginx config
sudo cp stack/oweb/nginx.conf /etc/nginx/conf.d/oweb.conf
sudo systemctl reload nginx
```

### Local Development

```bash
pip install -e ".[dev]"

# Run the API locally
uvicorn core.api.server:app --reload --port 8000

# Run the worker locally
python -m core.eng.worker
```
