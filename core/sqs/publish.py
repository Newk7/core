import os
import json
from core.sqs.get_client import get_sqs_client, get_queue_url
from core.log import create_log

log = create_log('sqs.publish')


def publish_task(task_data: dict, queue_name: str = None, queue_url: str = None, sqs_client=None) -> str:
    """
    Publish a task message to the SQS task queue.

    :param task_data: dict to serialize as JSON message body
    :param queue_name: SQS queue name (resolved to URL if queue_url not provided)
    :param queue_url: direct queue URL (takes precedence over queue_name)
    :param sqs_client: optional boto3 SQS client
    :return: SQS message ID
    """
    if sqs_client is None:
        sqs_client = get_sqs_client()

    if queue_url is None:
        if queue_name is None:
            env = os.getenv('ENV_NAME', 'prod')
            queue_name = f'biz-tool-{env}-task-queue'
        queue_url = get_queue_url(queue_name, sqs_client)

    body = json.dumps(task_data, default=str)
    log.info(f'publishing to {queue_url} body_len: {len(body)}')

    response = sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=body,
    )
    message_id = response['MessageId']
    log.info(f'published message_id: {message_id}')
    return message_id


def publish_result(result_data: dict, queue_name: str = None, queue_url: str = None, sqs_client=None) -> str:
    """
    Publish a result notification to the SQS result queue.

    :param result_data: dict to serialize as JSON message body
    :param queue_name: SQS queue name
    :param queue_url: direct queue URL
    :param sqs_client: optional boto3 SQS client
    :return: SQS message ID
    """
    if sqs_client is None:
        sqs_client = get_sqs_client()

    if queue_url is None:
        if queue_name is None:
            env = os.getenv('ENV_NAME', 'prod')
            queue_name = f'biz-tool-{env}-result-queue'
        queue_url = get_queue_url(queue_name, sqs_client)

    body = json.dumps(result_data, default=str)
    log.info(f'publishing result to {queue_url}')

    response = sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=body,
    )
    return response['MessageId']
