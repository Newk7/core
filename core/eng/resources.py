import os
from psycopg2 import pool
from core.db.get_db_pool import get_db_pool
from core.s3.get_client import get_s3_client
from core.sqs.get_client import get_sqs_client
from core.log import create_log

log = create_log('er')


class EngResources:
    """
    Central resource manager for the engine.
    Holds shared clients: DB pool, SQS client, S3 client.
    """

    def __init__(
        self,
        env_name: str = None,
        db_task_enabled: bool = True,
        db_pool_task: pool.SimpleConnectionPool = None,
        sqs_client=None,
        s3_enabled: bool = False,
        s3_client_task=None,
    ):
        self.env_name = env_name or os.getenv('ENV_NAME', 'dev')
        self.db_task_enabled = db_task_enabled
        self.db_pool_task = db_pool_task
        self.sqs_client = sqs_client
        self.s3_enabled = s3_enabled
        self.s3_client_task = s3_client_task

        log.info(f'init er env: {self.env_name}')

        if self.db_pool_task is None and self.db_task_enabled:
            try:
                self.db_pool_task = get_db_pool(env_name=self.env_name)
            except Exception as e:
                log.error(f'failed to get db task pool: {e}')
                raise e

        if self.sqs_client is None:
            try:
                self.sqs_client = get_sqs_client()
            except Exception as e:
                log.error(f'failed to get sqs client: {e}')
                raise e

        if self.s3_enabled and self.s3_client_task is None:
            try:
                self.s3_client_task = get_s3_client()
            except Exception as e:
                log.error(f'failed to get s3 client: {e}')
                self.s3_enabled = False
                raise e

    def get_db_pool_tasks(self):
        return self.db_pool_task

    def get_sqs_client(self):
        return self.sqs_client

    def get_s3_client_tasks(self):
        return self.s3_client_task

    def get_env_name(self):
        return self.env_name
