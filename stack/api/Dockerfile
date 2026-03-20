FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    libpoppler-cpp-dev \
    poppler-utils \
    libmagic1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first (cached unless pyproject.toml changes)
COPY pyproject.toml .
RUN mkdir -p core && touch core/__init__.py && \
    pip install --no-cache-dir --retries 3 --timeout 120 . && \
    rm -rf core

# Copy app code
COPY core/ core/

EXPOSE 8000

CMD ["uvicorn", "core.api.server:app", "--host", "0.0.0.0", "--port", "8000"]
