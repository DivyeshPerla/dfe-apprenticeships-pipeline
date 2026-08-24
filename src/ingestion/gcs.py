"""GCS helpers for the bronze landing zone.

Layout note: data files and sidecar metadata are deliberately kept under
separate top-level prefixes:

    <prefix>/data/version=<X>/ingest_date=<Y>/data.csv
    <prefix>/_meta/version=<X>/ingest_date=<Y>/{meta.json,_manifest.json}

BigQuery external tables allow only a single wildcard in a source URI, so a
mixed prefix would force `<prefix>/*/*/data.csv` (rejected) or `<prefix>/*`
(which would try to CSV-parse the JSON sidecars). Splitting the prefixes lets
the external table use `<prefix>/data/*` with AUTO hive partitioning, which
exposes `version` and `ingest_date` as real queryable columns for free.
"""

from __future__ import annotations

import logging
import os

from google.cloud import storage

log = logging.getLogger(__name__)

_CONTENT_TYPES = {
    ".csv": "text/csv",
    ".json": "application/json",
}

DATA_PREFIX = "data"
META_PREFIX = "_meta"


def _route(filename: str) -> str:
    """Data files go to the hive-partitioned data prefix; everything else to _meta."""
    return DATA_PREFIX if filename.endswith(".csv") else META_PREFIX


def upload_partition(
    local_dir: str, bucket_name: str, base_prefix: str, partition: str
) -> list[str]:
    """Upload `local_dir` into the split bronze layout.

    `partition` is the hive fragment, e.g. "version=2.0.2/ingest_date=2026-08-24".
    Returns the gs:// URIs written.
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    written: list[str] = []

    for name in sorted(os.listdir(local_dir)):
        path = os.path.join(local_dir, name)
        if not os.path.isfile(path):
            continue

        key = f"{base_prefix.strip('/')}/{_route(name)}/{partition.strip('/')}/{name}"
        blob = bucket.blob(key)
        ext = os.path.splitext(name)[1]
        if ext in _CONTENT_TYPES:
            blob.content_type = _CONTENT_TYPES[ext]

        blob.upload_from_filename(path)
        uri = f"gs://{bucket_name}/{key}"
        log.info("uploaded %s (%s bytes)", uri, os.path.getsize(path))
        written.append(uri)

    return written
