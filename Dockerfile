# Single image serving every pipeline job. Each Cloud Run Job overrides
# `command`/`args`, so ingestion and dbt share one build and one registry
# entry -- which also keeps Artifact Registry inside its 0.5 GB free tier.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements-ingest.txt requirements-dbt.txt ./
RUN pip install --no-cache-dir -r requirements-ingest.txt -r requirements-dbt.txt

COPY src/ ./src/
COPY dbt/ ./dbt/

ENV PYTHONPATH=/app/src \
    DBT_PROFILES_DIR=/app/dbt

# dbt writes target/ and logs/ at runtime; Cloud Run's filesystem is writable.
WORKDIR /app/dbt
RUN dbt deps --profiles-dir /app/dbt || true
WORKDIR /app

# Cloud Run Jobs run to completion; no server, no port.
CMD ["python", "-m", "ingestion.extract", "--help"]
