import os
import re
import uuid
from tempfile import mkdtemp
from pathlib import Path
from datetime import datetime, timezone
from io import BytesIO
from core.log import create_log

log = create_log('dlc.md')


def prune_non_alphanumeric_and_control(input_string):
    """Remove control characters except newline and tab."""
    allowed = {'\n', '\t'}
    return ''.join(
        char for char in input_string
        if (32 <= ord(char) < 127) or (char in allowed)
    )


def convert_file_to_markdown(file_path: str) -> str:
    """
    Convert a file to markdown using Docling with default settings.

    :param file_path: path to file (PDF, DOCX, HTML, etc.)
    :return: markdown string
    """
    from docling.datamodel.base_models import DocumentStream
    from docling.document_converter import DocumentConverter

    try:
        log.info(f'convert file: {file_path} to md')
        with open(file_path, 'rb') as f:
            buf = BytesIO(f.read())
            source = DocumentStream(name=file_path, stream=buf)
            converter = DocumentConverter()
            result = converter.convert(source)
            markdown = result.document.export_to_markdown()
            log.info(f'done convert file {file_path} to md: {len(markdown)} chars')
            return prune_non_alphanumeric_and_control(markdown)
    except Exception as e:
        log.error(f"failed to convert file {file_path} to md: {e}")
        raise


def convert_to_markdown(file_path: str, model: str = None, num_threads: int = 12,
                        bbox_enabled: bool = True, cpu_enabled: bool = True,
                        gpu_enabled: bool = False, tk=None):
    """
    Convert a file to markdown with full pipeline options (OCR, table extraction, bbox).

    :param file_path: path to file
    :param model: OCR model ('tesseract', 'easy', 'rapid', 'ocrmac')
    :param num_threads: worker threads for accelerator
    :param bbox_enabled: save bounding box JSON artifacts
    :param cpu_enabled: use CPU accelerator
    :param gpu_enabled: use CUDA GPU accelerator
    :param tk: optional Task for status tracking
    :return: tuple(markdown_text, preproc_artifacts: dict, tk)
    """
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import (
        AcceleratorDevice, AcceleratorOptions, PdfPipelineOptions,
        EasyOcrOptions, TesseractCliOcrOptions, TesseractOcrOptions,
        OcrMacOptions, RapidOcrOptions,
    )
    from docling.document_converter import (
        DocumentConverter, PdfFormatOption, WordFormatOption,
    )
    from docling.pipeline.simple_pipeline import SimplePipeline

    preproc_artifacts = {}
    try:
        use_threads = num_threads or int(os.getenv('DL_WORKER_THREADS', '12'))
        log.info(f'conv file: {file_path} model: {model} cpu: {cpu_enabled} gpu: {gpu_enabled} threads: {use_threads}')

        pipeline_options = PdfPipelineOptions()
        pipeline_options.images_scale = 2.0
        pipeline_options.generate_page_images = True
        pipeline_options.do_ocr = True
        pipeline_options.do_table_structure = True
        pipeline_options.table_structure_options.do_cell_matching = True

        # OCR engine selection
        if model is None or model == 'tesseract':
            ocr_options = TesseractCliOcrOptions(force_full_page_ocr=True)
        elif model == 'easy':
            ocr_options = EasyOcrOptions(force_full_page_ocr=True)
        elif model == 'trt':
            ocr_options = TesseractOcrOptions(force_full_page_ocr=True)
        elif model == 'ocrmac':
            ocr_options = OcrMacOptions(force_full_page_ocr=True)
        elif model == 'rapid':
            from huggingface_hub import snapshot_download
            download_path = snapshot_download(repo_id="SWHL/RapidOCR")
            ocr_options = RapidOcrOptions(
                det_model_path=os.path.join(download_path, "PP-OCRv4", "en_PP-OCRv3_det_infer.onnx"),
                rec_model_path=os.path.join(download_path, "PP-OCRv4", "ch_PP-OCRv4_rec_server_infer.onnx"),
                cls_model_path=os.path.join(download_path, "PP-OCRv3", "ch_ppocr_mobile_v2.0_cls_train.onnx"),
                force_full_page_ocr=True,
            )
        else:
            ocr_options = TesseractCliOcrOptions(force_full_page_ocr=True)
        pipeline_options.ocr_options = ocr_options

        # Accelerator
        if gpu_enabled:
            acc = AcceleratorOptions(num_threads=use_threads, device=AcceleratorDevice.CUDA)
            pipeline_options.accelerator_options = acc
            pipeline_options.accelerator_options.cuda_use_flash_attention2 = True
        else:
            acc = AcceleratorOptions(num_threads=use_threads, device=AcceleratorDevice.CPU)
            pipeline_options.accelerator_options = acc

        converter = DocumentConverter(
            allowed_formats=[
                InputFormat.PDF, InputFormat.IMAGE, InputFormat.DOCX,
                InputFormat.HTML, InputFormat.PPTX, InputFormat.ASCIIDOC,
                InputFormat.CSV, InputFormat.MD,
            ],
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options),
                InputFormat.DOCX: WordFormatOption(pipeline_cls=SimplePipeline),
            },
        )

        log.info(f'converting: {file_path}')
        doc_conv = converter.convert(source=file_path)
        doc = doc_conv.document
        text_content = doc.export_to_markdown()
        ret_text = prune_non_alphanumeric_and_control(text_content) if text_content else None

        if bbox_enabled and ret_text:
            file_name = os.path.basename(file_path)
            out_base_dir = str(Path(mkdtemp()))
            now = datetime.now(timezone.utc)
            use_file_dir = f'{out_base_dir}/bbox/{now.strftime("%Y/%m/%d")}'
            use_id = str(uuid.uuid4()).replace('-', '')
            use_file_name = f'{use_id}_{file_name}.bbox.{now.strftime("%Y%m%d%H%M%S")}.json'
            use_file_path = f'{use_file_dir}/{use_file_name}'
            os.makedirs(use_file_dir, exist_ok=True)

            doc.save_as_json(use_file_path)
            preproc_artifacts.setdefault('ing_files', []).append({
                'name': use_file_name,
                'file_path': use_file_path,
                'type': 'nlp_vg_bbox',
            })
            preproc_artifacts.setdefault('nlp_vg', {}).setdefault('bbox', {})[use_file_name] = use_file_path

        return ret_text, preproc_artifacts, tk
    except Exception as e:
        log.error(f"failed to convert file {file_path} to md: {e}")
        raise
