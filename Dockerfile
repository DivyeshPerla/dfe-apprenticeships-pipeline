# Slim base keeps the pushed image well inside Artifact Registry's 0.5 GB
# always-free allowance.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Only the ingestion runtime deps -- dbt is not needed in this image.
COPY requirements-ingest.txt .
RUN pip install --no-cache-dir -r requirements-ingest.txt

COPY src/ ./src/
ENV PYTHONPATH=/app/src

# Cloud Run Jobs run to completion; no server, no port.
# One image serves both jobs -- the module is supplied as container args so
# extract and version_watcher share a single build and a single registry entry.
ENTRYPOINT ["python"]
CMD ["-m", "ingestion.extract", "--help"]
