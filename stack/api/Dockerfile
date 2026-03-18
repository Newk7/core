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

RUN pip install --no-cache-dir ".[soc]"

EXPOSE 8000

CMD ["uvicorn", "core.api.server:app", "--host", "0.0.0.0", "--port", "8000"]
