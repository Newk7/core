from io import BytesIO
from core.s3.get_client import get_s3_client
from core.log import create_log

log = create_log(__name__)


def download_file(bk: str, key: str, s3_client=None):
    """
    Download a file from S3 into memory.

    :param bk: S3 bucket name
    :param key: S3 object key
    :param s3_client: optional boto3 S3 client
    :return: tuple(file_content: str | None, s3_client)
    """
    if s3_client is None:
        s3_client = get_s3_client()
    try:
        log.info(f's3_dl: s3://{bk}/{key}')
        response = s3_client.get_object(Bucket=bk, Key=key)
        file_content_bytes = BytesIO(response['Body'].read()).read()
        if file_content_bytes is not None:
            return file_content_bytes.decode('utf-8'), s3_client
        return None, s3_client
    except Exception as e:
        log.error(f"failed downloading file from s3: {e}")
        raise
