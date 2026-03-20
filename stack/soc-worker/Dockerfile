FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first (cached unless pyproject.toml changes)
COPY pyproject.toml .
RUN mkdir -p core && touch core/__init__.py && \
    pip install --no-cache-dir --retries 3 --timeout 120 ".[soc]" && \
    rm -rf core

# Copy app code
COPY core/ core/

CMD ["python", "-m", "core.soc.main", "agent"]
