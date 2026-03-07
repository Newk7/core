import os
import uuid
import time
import json
from datetime import datetime, timezone
from typing import List
from psycopg2 import pool
from psycopg2.extras import Json
from core.log import create_log
from core.sqs.publish import publish_result

log = create_log('task')


class Task:
    """
    Task lifecycle model for the biz-tool pipeline.

    Mirrors the postgres tasks table schema. Uses SQS for status updates
    and result notifications instead of Redis pub/sub.
    """

    def __init__(
        self,
        type: str,
        msg: str = None,
        model: str = None,
        id: str = None,
        answer: str = None,
        s3_locs: list[str] = None,
        s3_out_locs: dict = None,
        local_locs: List[str] = None,
        local_out_locs: dict = None,
        meta: dict = None,
        labels: dict = None,
        tags: dict = None,
        keywords: dict = None,
        entities: dict = None,
        summary: str = None,
        title: str = None,
        user_id: str = None,
        email: str = None,
        token: str = None,
        groups: dict = None,
        status: int = -999,
        display_status: str = None,
        err: str = None,
        parent_id: str = None,
        tracking_id: str = None,
        worker: str = None,
        manifest_loc: str = None,
        duration: int = None,
        in_args: dict = None,
        created: str = None,
        updated: str = None,
        version: str = None,
        db_enabled: bool = True,
        s3_enabled: bool = True,
        sqs_message_id: str = None,
        er=None,
        **kwargs,
    ):
        self.id = id or str(uuid.uuid4())
        self.type = type
        self.model = model
        self.msg = msg
        self.answer = answer
        self.s3_locs = s3_locs
        self.s3_out_locs = s3_out_locs
        self.local_locs = local_locs
        self.local_out_locs = local_out_locs
        self.meta = meta or {}
        self.labels = labels
        self.tags = tags
        self.keywords = keywords
        self.entities = entities
        self.summary = summary
        self.title = title
        self.user_id = user_id
        self.email = email
        self.token = token
        self.groups = groups
        self.status = status
        self.display_status = display_status
        self.err = err
        self.parent_id = parent_id
        self.tracking_id = tracking_id
        self.worker = worker
        self.manifest_loc = manifest_loc
        self.duration = duration
        self.in_args = in_args or {}
        self.sqs_message_id = sqs_message_id
        self.db_enabled = db_enabled
        self.s3_enabled = s3_enabled
        self.er = er
        self.created = created or datetime.now(timezone.utc).isoformat()
        self.updated = updated
        self.version = version

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'type': self.type,
            'model': self.model,
            'msg': self.msg,
            'answer': self.answer,
            's3_locs': self.s3_locs,
            's3_out_locs': self.s3_out_locs,
            'local_locs': self.local_locs,
            'local_out_locs': self.local_out_locs,
            'meta': self.meta,
            'labels': self.labels,
            'tags': self.tags,
            'keywords': self.keywords,
            'entities': self.entities,
            'summary': self.summary,
            'title': self.title,
            'user_id': self.user_id,
            'email': self.email,
            'groups': self.groups,
            'status': self.status,
            'display_status': self.display_status,
            'err': self.err,
            'parent_id': self.parent_id,
            'tracking_id': self.tracking_id,
            'worker': self.worker,
            'manifest_loc': self.manifest_loc,
            'duration': self.duration,
            'in_args': self.in_args,
            'sqs_message_id': self.sqs_message_id,
            'created': self.created,
            'updated': self.updated,
            'version': self.version,
        }

    def get_job_type(self) -> str:
        if self.type is None:
            return 'chat'
        t = self.type.lower()
        if 'shred' in t:
            return 'shred'
        return t

    def get_in_args(self) -> dict:
        return self.in_args or {}

    def get_task_s3_dir(self) -> tuple[str, str]:
        bucket = os.getenv('TASK_BUCKET', 'biz-tool-prod-task-data')
        prefix = f'tasks/{self.id}'
        return bucket, prefix

    def pub_update(self, s: int = None, ds: str = None, answer: str = None, err: str = None, verbose: bool = False):
        """Publish a status update. Sends result to SQS result queue."""
        if s is not None:
            self.status = s
        if ds is not None:
            self.display_status = ds
        if answer is not None:
            self.answer = answer
        if err is not None:
            self.err = err
        self.updated = datetime.now(timezone.utc).isoformat()

        if verbose:
            log.info(f'update tk.id: {self.id} s: {self.status} ds: {self.display_status}')

        try:
            publish_result(result_data={
                'task_id': self.id,
                'status': self.status,
                'display_status': self.display_status,
                'err': self.err,
                'updated': self.updated,
            })
        except Exception as e:
            log.warning(f'failed to publish result update for tk.id: {self.id}: {e}')

    def insert(self, db_pool: pool.SimpleConnectionPool):
        """Insert this task into the postgres tasks table."""
        if not self.db_enabled or db_pool is None:
            return
        conn = db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO tasks (id, status, task_type, payload, s3_manifest_key, sqs_message_id, metadata)
                       VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                    (
                        self.id,
                        'pending',
                        self.type,
                        Json(self.to_dict()),
                        self.manifest_loc,
                        self.sqs_message_id,
                        Json(self.meta),
                    )
                )
            conn.commit()
            log.info(f'inserted task {self.id}')
        except Exception as e:
            conn.rollback()
            log.error(f'failed to insert task {self.id}: {e}')
        finally:
            db_pool.putconn(conn)

    def update(self, db_pool: pool.SimpleConnectionPool):
        """Update this task in the postgres tasks table."""
        if not self.db_enabled or db_pool is None:
            return
        status_map = {0: 'completed', -999: 'pending'}
        db_status = 'failed' if self.status < 0 and self.status != -999 else status_map.get(self.status, 'processing')

        conn = db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    """UPDATE tasks
                       SET status = %s, payload = %s, error_message = %s,
                           s3_manifest_key = %s, retry_count = retry_count,
                           metadata = %s, updated_at = NOW(),
                           completed_at = CASE WHEN %s = 'completed' THEN NOW() ELSE completed_at END
                       WHERE id = %s""",
                    (
                        db_status,
                        Json(self.to_dict()),
                        self.err,
                        self.manifest_loc,
                        Json(self.meta),
                        db_status,
                        self.id,
                    )
                )
            conn.commit()
        except Exception as e:
            conn.rollback()
            log.error(f'failed to update task {self.id}: {e}')
        finally:
            db_pool.putconn(conn)

    def pub_manifest(self, s3_client=None) -> tuple[bool, str]:
        """Upload this task's manifest to S3."""
        from core.s3.upload_file import upload_file
        import tempfile

        bucket, prefix = self.get_task_s3_dir()
        s3_loc = f's3://{bucket}/{prefix}/manifest.json'

        tmp = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
        try:
            json.dump(self.to_dict(), tmp, default=str, indent=2)
            tmp.close()
            success, loc = upload_file(local_path=tmp.name, s3_loc=s3_loc, s3_client=s3_client)
            if success:
                self.manifest_loc = loc
            return success, loc
        finally:
            os.unlink(tmp.name)
