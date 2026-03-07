import os
from datetime import datetime, timezone
from core.s3.get_client import get_s3_client
from core.log import create_log

log = create_log(__name__)


def upload_file(local_path: str, bk: str = None, s3_loc: str = None, encryption_type: str = 'AES256', storage_class: str = None, s3_client=None) -> tuple[bool, str]:
    """
    Upload a local file to S3 with AES256 encryption by default.

    :param local_path: path to local file
    :param bk: optional bucket name (used if s3_loc is None)
    :param s3_loc: full s3://bucket/prefix/key path
    :param encryption_type: server-side encryption type
    :param storage_class: S3 storage class
    :param s3_client: optional existing boto3 S3 client
    :return: tuple(success: bool, s3_location: str | None)
    """
    try:
        if s3_client is None:
            s3_client = get_s3_client()
        if storage_class is None:
            storage_class = os.getenv('STORAGE_CLASS', 'STANDARD_IA')

        if s3_loc is not None:
            scrub = s3_loc.replace('s3://', '').split('/')
            bk = scrub[0]
            new_key = '/'.join(scrub[1:])
        else:
            date_prefix = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
            filename = os.path.basename(local_path)
            new_key = f"{bk}/data/{date_prefix}_{filename}"

        log.info(f"uploading {local_path} to s3://{bk}/{new_key} sc: {storage_class}")

        text_exts = {'.txt', '.py', '.md', '.json', '.yaml', '.yml', '.csv', '.html', '.xml', '.toml', '.cfg', '.ini', '.conf', '.sql'}
        ext = os.path.splitext(local_path)[1].lower()
        mode = 'r' if ext in text_exts else 'rb'

        with open(local_path, mode) as f:
            s3_client.put_object(
                Bucket=bk,
                Key=new_key,
                Body=f.read() if mode == 'r' else f,
                ServerSideEncryption=encryption_type,
                StorageClass=storage_class,
            )
        log.info(f"uploaded to s3://{bk}/{new_key}")
        return True, f's3://{bk}/{new_key}'
    except Exception as e:
        log.error(f"failed uploading file: {e}")
        return False, None
