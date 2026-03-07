import os
import boto3
from core.log import create_log

log = create_log('sqs.get_client')


def get_sqs_client(region: str = None):
    """Get a boto3 SQS client."""
    if region is None:
        region = os.getenv('AWS_REGION', 'us-east-1')
    try:
        return boto3.client('sqs', region_name=region)
    except Exception as e:
        log.error(f'failed to get sqs client: {e}')
        raise e


def get_queue_url(queue_name: str, sqs_client=None) -> str:
    """Resolve a queue name to its URL."""
    if sqs_client is None:
        sqs_client = get_sqs_client()
    try:
        response = sqs_client.get_queue_url(QueueName=queue_name)
        return response['QueueUrl']
    except Exception as e:
        log.error(f'failed to get queue url for {queue_name}: {e}')
        raise e
