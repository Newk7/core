import os
import uuid
from datetime import datetime, timezone
from typing import Optional
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from core.log import create_log
from core.jobs.task import Task
from core.sqs.publish import publish_task
from core.eng.resources import EngResources

log = create_log('api')

app = FastAPI(title="BizTool Core API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv('CORS_ORIGINS', '*').split(','),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# lazy-init shared resources
_er: Optional[EngResources] = None


def get_er() -> EngResources:
    global _er
    if _er is None:
        _er = EngResources(
            db_task_enabled=os.getenv('DB_ENABLED', '1') == '1',
            s3_enabled=os.getenv('S3_ENABLED', '1') == '1',
        )
    return _er


# --- Request/Response Models ---

class TaskCreateRequest(BaseModel):
    type: str
    msg: Optional[str] = None
    model: Optional[str] = None
    user_id: Optional[str] = None
    email: Optional[str] = None
    s3_locs: Optional[list[str]] = None
    in_args: Optional[dict] = None
    meta: Optional[dict] = None
    labels: Optional[dict] = None
    tags: Optional[dict] = None


class TaskResponse(BaseModel):
    id: str
    type: str
    status: int
    display_status: Optional[str] = None
    sqs_message_id: Optional[str] = None
    created: Optional[str] = None


class TaskStatusResponse(BaseModel):
    id: str
    status: str
    task_type: str
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    completed_at: Optional[str] = None
    error_message: Optional[str] = None
    payload: Optional[dict] = None


class HealthResponse(BaseModel):
    status: str
    timestamp: str
    version: str = "0.1.0"


# --- Routes ---

@app.get("/health", response_model=HealthResponse)
def health():
    return HealthResponse(
        status="ok",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


@app.post("/api/v1/tasks", response_model=TaskResponse)
def create_task(req: TaskCreateRequest):
    """Create a new task and publish it to SQS."""
    er = get_er()

    tk = Task(
        type=req.type,
        msg=req.msg,
        model=req.model,
        user_id=req.user_id,
        email=req.email,
        s3_locs=req.s3_locs,
        in_args=req.in_args or {},
        meta=req.meta or {},
        labels=req.labels,
        tags=req.tags,
        db_enabled=er.db_task_enabled,
        s3_enabled=er.s3_enabled,
    )

    # insert into DB
    if er.db_pool_task:
        tk.insert(er.db_pool_task)

    # publish to SQS
    try:
        msg_id = publish_task(
            task_data=tk.to_dict(),
            sqs_client=er.get_sqs_client(),
        )
        tk.sqs_message_id = msg_id
    except Exception as e:
        log.error(f'failed to publish task {tk.id} to SQS: {e}')
        raise HTTPException(status_code=500, detail=f'Failed to queue task: {e}')

    log.info(f'created task {tk.id} type: {tk.type} sqs_msg: {tk.sqs_message_id}')
    return TaskResponse(
        id=tk.id,
        type=tk.type,
        status=tk.status,
        display_status='queued',
        sqs_message_id=tk.sqs_message_id,
        created=tk.created,
    )


@app.get("/api/v1/tasks/{task_id}", response_model=TaskStatusResponse)
def get_task(task_id: str):
    """Get task status from the database."""
    er = get_er()
    if not er.db_pool_task:
        raise HTTPException(status_code=503, detail='Database not available')

    conn = er.db_pool_task.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT id, status, task_type, created_at, updated_at,
                          completed_at, error_message, payload
                   FROM tasks WHERE id = %s""",
                (task_id,)
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail='Task not found')
            return TaskStatusResponse(
                id=str(row[0]),
                status=row[1],
                task_type=row[2],
                created_at=row[3].isoformat() if row[3] else None,
                updated_at=row[4].isoformat() if row[4] else None,
                completed_at=row[5].isoformat() if row[5] else None,
                error_message=row[6],
                payload=row[7],
            )
    finally:
        er.db_pool_task.putconn(conn)


@app.get("/api/v1/tasks")
def list_tasks(status: Optional[str] = None, task_type: Optional[str] = None, limit: int = 50):
    """List tasks with optional filters."""
    er = get_er()
    if not er.db_pool_task:
        raise HTTPException(status_code=503, detail='Database not available')

    conn = er.db_pool_task.getconn()
    try:
        with conn.cursor() as cur:
            query = "SELECT id, status, task_type, created_at, updated_at, error_message FROM tasks WHERE 1=1"
            params = []
            if status:
                query += " AND status = %s"
                params.append(status)
            if task_type:
                query += " AND task_type = %s"
                params.append(task_type)
            query += " ORDER BY created_at DESC LIMIT %s"
            params.append(limit)

            cur.execute(query, params)
            rows = cur.fetchall()
            return [
                {
                    'id': str(r[0]),
                    'status': r[1],
                    'task_type': r[2],
                    'created_at': r[3].isoformat() if r[3] else None,
                    'updated_at': r[4].isoformat() if r[4] else None,
                    'error_message': r[5],
                }
                for r in rows
            ]
    finally:
        er.db_pool_task.putconn(conn)


@app.post("/api/v1/upload")
async def upload_file_endpoint(
    file: UploadFile = File(...),
    task_type: str = Form(default="shred"),
    user_id: str = Form(default=None),
):
    """Upload a file, store in S3, and create a shred task."""
    er = get_er()

    # save uploaded file locally
    import tempfile
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{file.filename}')
    try:
        content = await file.read()
        tmp.write(content)
        tmp.close()

        # upload to S3
        task_id = str(uuid.uuid4())
        s3_loc = None
        if er.s3_enabled and er.s3_client_task:
            bucket = os.getenv('TASK_BUCKET', 'biz-tool-prod-task-data')
            s3_key = f'tasks/{task_id}/input/{file.filename}'
            from core.s3.upload_file import upload_file
            success, loc = upload_file(
                local_path=tmp.name,
                s3_loc=f's3://{bucket}/{s3_key}',
                s3_client=er.s3_client_task,
            )
            if success:
                s3_loc = loc

        # create task
        tk = Task(
            id=task_id,
            type=task_type,
            msg=f'process file: {file.filename}',
            user_id=user_id,
            s3_locs=[s3_loc] if s3_loc else None,
            in_args={'s3': s3_loc or '', 'local_paths': [tmp.name] if not s3_loc else []},
            db_enabled=er.db_task_enabled,
            s3_enabled=er.s3_enabled,
        )

        if er.db_pool_task:
            tk.insert(er.db_pool_task)

        msg_id = publish_task(task_data=tk.to_dict(), sqs_client=er.get_sqs_client())

        return {
            'task_id': tk.id,
            'filename': file.filename,
            's3_loc': s3_loc,
            'sqs_message_id': msg_id,
            'status': 'queued',
        }
    finally:
        os.unlink(tmp.name)
