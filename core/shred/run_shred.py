import os
import uuid
import json
from tempfile import mkdtemp
from datetime import datetime, timezone
from core.log import create_log
from core.s3.download_s3_keys import download_s3_keys
from core.s3.upload_file import upload_file
from core.docling.convert_file_to_markdown import convert_to_markdown, convert_file_to_markdown
from core.jobs.task import Task

log = create_log('shred')


def run_shred(tk: Task, er=None, verbose: bool = False) -> tuple[int, Task]:
    """
    Shred documents into structured data.

    Downloads files from S3 (or uses local paths), converts to markdown,
    and writes results as parquet.

    :param tk: Task with in_args containing s3 locs or local file paths
    :param er: EngResources
    :param verbose: enable verbose logging
    :return: tuple(status_code, updated Task)
    """
    in_args = tk.get_in_args()
    s3_locs_str = in_args.get('s3', '')
    local_paths = in_args.get('local_paths', [])
    bbox_enabled = in_args.get('bbox_enabled', True)
    ocr_model = in_args.get('ocr_model', None)

    dl_dir = mkdtemp(prefix='shred_')
    files_to_process = []

    # download from S3 if provided
    if s3_locs_str:
        s3_locs = [s.strip() for s in s3_locs_str.split(',') if s.strip()]
        if s3_locs:
            tk.pub_update(s=150, ds=f'downloading {len(s3_locs)} files from s3')
            s3_client = er.get_s3_client_tasks() if er else None
            downloaded, s3_client = download_s3_keys(s3_locs=s3_locs, dl_dir=dl_dir, s3_client=s3_client)
            files_to_process.extend(downloaded)

    # add local paths
    if local_paths:
        files_to_process.extend(local_paths)

    if not files_to_process:
        log.warning(f'no files to process for tk.id: {tk.id}')
        tk.pub_update(s=-100, ds='no files to process')
        return -100, tk

    log.info(f'shredding {len(files_to_process)} files for tk.id: {tk.id}')
    tk.pub_update(s=200, ds=f'processing {len(files_to_process)} files')

    results = []
    for file_path in files_to_process:
        try:
            file_name = os.path.basename(file_path)
            log.info(f'processing: {file_name}')

            md_text, preproc_artifacts, tk = convert_to_markdown(
                file_path=file_path,
                model=ocr_model,
                bbox_enabled=bbox_enabled,
                tk=tk,
            )

            if md_text:
                results.append({
                    'file': file_name,
                    'markdown_len': len(md_text),
                    'markdown': md_text,
                    'artifacts': preproc_artifacts,
                })
                log.info(f'converted {file_name}: {len(md_text)} chars')
            else:
                log.warning(f'no content extracted from {file_name}')
        except Exception as e:
            log.error(f'failed to process {file_path}: {e}')
            results.append({
                'file': os.path.basename(file_path),
                'error': str(e),
            })

    # write results to parquet
    tk.pub_update(s=300, ds='writing results to parquet')
    try:
        pq_path = write_results_to_parquet(results, dl_dir, tk.id)
        if pq_path and tk.s3_enabled:
            bucket, prefix = tk.get_task_s3_dir()
            s3_loc = f's3://{bucket}/{prefix}/shred_results.parquet'
            s3_client = er.get_s3_client_tasks() if er else None
            success, loc = upload_file(local_path=pq_path, s3_loc=s3_loc, s3_client=s3_client)
            if success:
                tk.s3_out_locs = tk.s3_out_locs or {}
                tk.s3_out_locs['parquet'] = loc

        # upload individual bbox artifacts
        for r in results:
            artifacts = r.get('artifacts', {})
            for ing_file in artifacts.get('ing_files', []):
                if tk.s3_enabled and ing_file.get('file_path'):
                    bucket, prefix = tk.get_task_s3_dir()
                    art_s3_loc = f's3://{bucket}/{prefix}/artifacts/{ing_file["name"]}'
                    s3_client = er.get_s3_client_tasks() if er else None
                    upload_file(local_path=ing_file['file_path'], s3_loc=art_s3_loc, s3_client=s3_client)

    except Exception as e:
        log.error(f'failed writing parquet for tk.id: {tk.id}: {e}')

    processed = sum(1 for r in results if 'error' not in r)
    tk.pub_update(s=0, ds=f'shredded {processed}/{len(files_to_process)} files')
    tk.meta['shred_results_count'] = len(results)
    tk.meta['shred_processed_count'] = processed

    return 0, tk


def write_results_to_parquet(results: list[dict], out_dir: str, task_id: str) -> str:
    """
    Write shred results to a parquet file.

    :param results: list of result dicts with file, markdown, etc.
    :param out_dir: output directory
    :param task_id: task ID for naming
    :return: path to parquet file
    """
    try:
        import pandas as pd

        rows = []
        for r in results:
            rows.append({
                'task_id': task_id,
                'file': r.get('file'),
                'markdown': r.get('markdown', ''),
                'markdown_len': r.get('markdown_len', 0),
                'error': r.get('error'),
                'timestamp': datetime.now(timezone.utc).isoformat(),
            })

        df = pd.DataFrame(rows)
        pq_path = os.path.join(out_dir, f'{task_id}_shred.parquet')
        df.to_parquet(pq_path, index=False, engine='fastparquet')
        log.info(f'wrote {len(rows)} rows to {pq_path}')
        return pq_path
    except ImportError:
        log.warning('pandas/fastparquet not available, writing JSON fallback')
        json_path = os.path.join(out_dir, f'{task_id}_shred.json')
        with open(json_path, 'w') as f:
            json.dump(results, f, default=str, indent=2)
        return json_path
    except Exception as e:
        log.error(f'failed writing parquet: {e}')
        return None
