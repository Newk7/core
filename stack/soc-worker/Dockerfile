FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml .
COPY core/ core/

RUN pip install --no-cache-dir ".[soc]"

CMD ["python", "-m", "core.soc.main", "agent"]
