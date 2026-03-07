import os
from io import BytesIO
from core.s3.get_client import get_s3_client
from core.log import create_log

log = create_log(__name__)

TEXT_EXTS = {'txt', 'text', 'md', 'py', 'rs', 'toml', 'config', 'conf', 'ini', 'json', 'yaml', 'yml', 'csv', 'html', 'xml', 'sql'}


def download_s3_keys(s3_locs: list[str], dl_dir: str, s3_client=None) -> tuple[list[str], object]:
    """
    Download files from S3 given their S3 URIs and save them locally.

    :param s3_locs: list of s3://bucket/key URIs
    :param dl_dir: local directory to save files
    :param s3_client: optional boto3 S3 client
    :return: tuple(list of local file paths, s3_client)
    """
    if s3_client is None:
        s3_client = get_s3_client()

    downloaded_files = []
    for s3_loc in s3_locs:
        try:
            if 's3://' in s3_loc:
                parts = s3_loc.split('s3://')[1].split('/')
            else:
                log.warning(f'unexpected s3 uri format: {s3_loc}')
                continue

            bucket = parts[0]
            key = '/'.join(parts[1:])
            local_file_path = os.path.join(dl_dir, os.path.basename(key))
            ext = local_file_path.rsplit('.', 1)[-1].lower() if '.' in local_file_path else ''

            os.makedirs(dl_dir, exist_ok=True)
            response = s3_client.get_object(Bucket=bucket, Key=key)
            file_content = BytesIO(response['Body'].read())

            if ext in TEXT_EXTS:
                with open(local_file_path, 'w') as f:
                    f.write(file_content.read().decode('utf-8'))
            else:
                with open(local_file_path, 'wb') as f:
                    f.write(file_content.read())

            downloaded_files.append(local_file_path)
            log.info(f"downloaded {s3_loc} to {local_file_path}")
        except Exception as e:
            log.error(f"failed to download {s3_loc}: {e}")

    log.info(f'downloaded {len(downloaded_files)}/{len(s3_locs)} files')
    return downloaded_files, s3_client
