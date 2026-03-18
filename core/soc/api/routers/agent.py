"""
Agent control routes — manual triggers publish tasks to SQS
for the soc-worker to pick up.
"""
import os
import uuid
from fastapi import APIRouter, HTTPException
from core.log import create_log

router = APIRouter()
log = create_log(__name__)


def _publish_soc_task(task_type: str, in_args: dict = None) -> dict:
    """Publish a SOC task to SQS using core's task infrastructure."""
    from core.jobs.task import Task
    from core.sqs.publish import publish_task
    from core.sqs.get_client import get_sqs_client

    env = os.getenv("ENV_NAME", "prod")
    task = Task()
    task.id = str(uuid.uuid4())
    task.type = task_type
    task.in_args = in_args or {}

    sqs_client = get_sqs_client()
    queue_name = f"biz-tool-{env}-task-queue"
    msg_id = publish_task(sqs_client, queue_name, task)

    return {"task_id": task.id, "sqs_message_id": msg_id, "type": task_type}


@router.post("/investigate")
def trigger_investigation(body: dict):
    prompt = body.get("prompt", "")
    if not prompt:
        raise HTTPException(400, "prompt required")
    result = _publish_soc_task("soc.investigate", {"prompt": prompt})
    return {"status": "queued", **result}


@router.post("/hunt")
def trigger_hunt():
    result = _publish_soc_task("soc.hunt")
    return {"status": "queued", **result}


@router.post("/ingest")
def trigger_ingest():
    result = _publish_soc_task("soc.ingest")
    return {"status": "queued", **result}


@router.post("/sync-assets")
def trigger_asset_sync(body: dict = {}):
    sources = body.get("sources") if body else None
    result = _publish_soc_task("soc.sync", {"sources": sources})
    return {"status": "queued", **result}
