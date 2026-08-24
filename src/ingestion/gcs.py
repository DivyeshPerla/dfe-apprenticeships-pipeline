"""GCS helpers for the bronze landing zone."""

from __future__ import annotations

import logging
import os

from google.cloud import storage

log = logging.getLogger(__name__)

# Content types matter: BigQuery external tables and the console preview both
# behave better when the object is not served as application/octet-stream.
_CONTENT_TYPES = {
    ".csv": "text/csv",
    ".json": "application/json",
}


def upload_dir(local_dir: str, bucket_name: str, prefix: str) -> list[str]:
    """Upload every file in `local_dir` to gs://bucket/prefix/ (non-recursive).

    Returns the list of gs:// URIs written.
    """
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    written: list[str] = []

    for name in sorted(os.listdir(local_dir)):
        path = os.path.join(local_dir, name)
        if not os.path.isfile(path):
            continue

        blob = bucket.blob(f"{prefix.rstrip('/')}/{name}")
        ext = os.path.splitext(name)[1]
        if ext in _CONTENT_TYPES:
            blob.content_type = _CONTENT_TYPES[ext]

        blob.upload_from_filename(path)
        uri = f"gs://{bucket_name}/{blob.name}"
        log.info("uploaded %s (%s bytes)", uri, os.path.getsize(path))
        written.append(uri)

    return written
