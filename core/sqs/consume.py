import os
import json
from core.sqs.get_client import get_sqs_client, get_queue_url
from core.log import create_log

log = create_log('sqs.consume')


def receive_messages(queue_name: str = None, queue_url: str = None, max_messages: int = 1,
                     wait_time: int = 20, visibility_timeout: int = 300, sqs_client=None) -> list[dict]:
    """
    Long-poll messages from an SQS queue.

    :param queue_name: SQS queue name
    :param queue_url: direct queue URL
    :param max_messages: max messages per poll (1-10)
    :param wait_time: long poll wait time in seconds
    :param visibility_timeout: how long the message is hidden after receipt
    :param sqs_client: optional boto3 SQS client
    :return: list of dicts with keys: message_id, receipt_handle, body (parsed JSON)
    """
    if sqs_client is None:
        sqs_client = get_sqs_client()

    if queue_url is None:
        if queue_name is None:
            env = os.getenv('ENV_NAME', 'prod')
            queue_name = f'biz-tool-{env}-task-queue'
        queue_url = get_queue_url(queue_name, sqs_client)

    response = sqs_client.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=max_messages,
        WaitTimeSeconds=wait_time,
        VisibilityTimeout=visibility_timeout,
    )

    messages = []
    for msg in response.get('Messages', []):
        try:
            body = json.loads(msg['Body'])
        except (json.JSONDecodeError, KeyError):
            body = msg.get('Body')
        messages.append({
            'message_id': msg['MessageId'],
            'receipt_handle': msg['ReceiptHandle'],
            'body': body,
        })

    if messages:
        log.info(f'received {len(messages)} messages from {queue_url}')
    return messages


def delete_message(receipt_handle: str, queue_name: str = None, queue_url: str = None, sqs_client=None):
    """
    Delete a message from SQS after successful processing.

    :param receipt_handle: the receipt handle from receive_messages
    :param queue_name: SQS queue name
    :param queue_url: direct queue URL
    :param sqs_client: optional boto3 SQS client
    """
    if sqs_client is None:
        sqs_client = get_sqs_client()

    if queue_url is None:
        if queue_name is None:
            env = os.getenv('ENV_NAME', 'prod')
            queue_name = f'biz-tool-{env}-task-queue'
        queue_url = get_queue_url(queue_name, sqs_client)

    sqs_client.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=receipt_handle,
    )
    log.info(f'deleted message from {queue_url}')
