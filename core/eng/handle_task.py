import os
import time
import json
from core.jobs.task import Task
from core.eng.resources import EngResources
from core.log import create_log

log = create_log(__name__)


def handle_task(tk: Task, er: EngResources = None, verbose: bool = False):
    """
    Dispatch and execute a task based on its job type.

    :param tk: Task instance
    :param er: EngResources with shared clients
    :param verbose: enable verbose logging
    :return: Task (updated with results)
    """
    job_type = tk.get_job_type()
    log.info(f'start tk.id: {tk.id} type: {job_type} model: {tk.model}')

    tk.pub_update(s=200, ds=f'starting task type: {job_type}')
    start_time = time.time()

    try:
        if job_type in ['shred', 'shred.3']:
            log.info(f'processing shred tk.id: {tk.id}')
            from core.shred.run_shred import run_shred
            task_status, tk = run_shred(tk=tk, er=er, verbose=verbose)
            log.info(f'done shred tk.id: {tk.id} status: {tk.status} ds: "{tk.display_status}"')

        elif job_type in ['contact']:
            log.info(f'processing contact email tk.id: {tk.id}')
            from core.jobs.send_contact_email import send_contact_email
            send_contact_email(tk)
            tk.pub_update(s=0, ds='contact email sent')

        elif job_type in ['chat']:
            log.info(f'processing chat tk.id: {tk.id}')
            # placeholder for LLM chat integration
            tk.pub_update(s=0, ds='chat processing not yet implemented')

        elif job_type.startswith('soc.'):
            log.info(f'SOC task {job_type} tk.id: {tk.id} — routed to soc-worker via SQS')
            # soc.* tasks are consumed by the soc-worker, not this worker.
            # If they arrive here, just acknowledge them.
            tk.pub_update(s=0, ds=f'soc task {job_type} acknowledged')

        else:
            log.error(f'unsupported job type: {job_type} for tk.id: {tk.id}')
            tk.pub_update(s=-2000, ds=f'unsupported job type: {job_type}')
            return tk

    except Exception as e:
        log.error(f'task failed tk.id: {tk.id} error: {e}')
        tk.pub_update(s=-654321, ds='task failed with exception', err=str(e))
        return tk

    tk.duration = int((time.time() - start_time) * 1000)

    if tk.status >= 0 or tk.status == -999:
        tk.pub_update(s=0, ds='done', verbose=True)

    # persist to DB and S3
    if er and er.db_pool_task:
        tk.update(er.db_pool_task)
    if tk.s3_enabled and er and er.s3_client_task:
        tk.pub_manifest(s3_client=er.s3_client_task)

    log.info(f'done tk.id: {tk.id} status: {tk.status} duration: {tk.duration}ms')
    return tk
