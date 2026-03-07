import os
import json
import signal
import sys
from core.sqs.consume import receive_messages, delete_message
from core.jobs.task import Task
from core.eng.resources import EngResources
from core.eng.handle_task import handle_task
from core.log import create_log

log = create_log('worker')

_running = True


def _signal_handler(sig, frame):
    global _running
    log.info('received shutdown signal, finishing current task...')
    _running = False


def worker(queue_name: str = None, er: EngResources = None, worker_name: str = 'worker-1'):
    """
    Main worker loop that polls SQS for tasks and processes them.

    :param queue_name: SQS queue name to poll
    :param er: EngResources with shared clients
    :param worker_name: identifier for this worker instance
    """
    global _running

    signal.signal(signal.SIGINT, _signal_handler)
    signal.signal(signal.SIGTERM, _signal_handler)

    if er is None:
        er = EngResources(s3_enabled=True)

    if queue_name is None:
        env = os.getenv('ENV_NAME', 'prod')
        queue_name = f'biz-tool-{env}-task-queue'

    log.info(f'starting {worker_name} polling queue: {queue_name}')

    while _running:
        try:
            messages = receive_messages(
                queue_name=queue_name,
                max_messages=1,
                wait_time=20,
                sqs_client=er.get_sqs_client(),
            )

            for msg in messages:
                task_data = msg['body']
                receipt_handle = msg['receipt_handle']

                log.info(f'{worker_name} received task: {task_data.get("id", "unknown")}')

                tk = Task(**task_data)
                tk.worker = worker_name
                tk.sqs_message_id = msg['message_id']
                tk.er = er

                # insert into DB
                if er.db_pool_task:
                    tk.insert(er.db_pool_task)

                tk = handle_task(tk=tk, er=er)

                # delete from queue on success
                delete_message(
                    receipt_handle=receipt_handle,
                    queue_name=queue_name,
                    sqs_client=er.get_sqs_client(),
                )
                log.info(f'{worker_name} completed task: {tk.id} status: {tk.status}')

        except Exception as e:
            log.error(f'{worker_name} error in poll loop: {e}')

    log.info(f'{worker_name} shutting down')


if __name__ == '__main__':
    worker()
