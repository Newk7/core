import boto3
from core.log import create_log

log = create_log('s3.get_client')


def get_s3_client():
    try:
        return boto3.client('s3')
    except Exception as e:
        log.error(f'failed to get s3 client with error: {e}')
        raise e
