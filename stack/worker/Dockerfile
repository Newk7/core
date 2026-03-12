FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    libpoppler-cpp-dev \
    poppler-utils \
    libmagic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml .
COPY core/ core/

RUN pip install --no-cache-dir .

CMD ["python", "-m", "core.eng.worker"]
