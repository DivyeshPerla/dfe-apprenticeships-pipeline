"""Detect a newly published dataset version and emit an event.

The source publishes roughly quarterly, so a fixed daily pipeline run would
re-process identical data ~90 times per release. This job instead polls the
cheap `/versions` endpoint, compares against the last version it saw (state
kept as a small JSON object in GCS), and publishes to Pub/Sub only when the
latest version actually changes.

Exit codes let Cloud Workflows branch without parsing stdout:
    0 -- new version detected (event published)
    3 -- no change
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import sys

from google.cloud import storage

from ingestion.dfe_client import APPRENTICESHIPS_DATASET_ID, DfEStatisticsClient

log = logging.getLogger(__name__)

STATE_OBJECT = "_state/last_seen_version.json"

EXIT_NEW_VERSION = 0
EXIT_NO_CHANGE = 3


def read_state(bucket_name: str, object_name: str = STATE_OBJECT) -> dict | None:
    blob = storage.Client().bucket(bucket_name).blob(object_name)
    if not blob.exists():
        return None
    return json.loads(blob.download_as_text())


def write_state(bucket_name: str, state: dict, object_name: str = STATE_OBJECT) -> None:
    blob = storage.Client().bucket(bucket_name).blob(object_name)
    # content_type must be passed to the upload call; setting it on the blob
    # first conflicts with upload_from_string's text/plain default.
    blob.upload_from_string(
        json.dumps(state, indent=2), content_type="application/json"
    )


def publish_event(project: str, topic: str, payload: dict) -> str:
    from google.cloud import pubsub_v1

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project, topic)
    future = publisher.publish(
        topic_path,
        json.dumps(payload).encode("utf-8"),
        # Attributes let subscribers filter without decoding the body.
        event_type="dataset_version_published",
        dataset_version=payload["latest_version"],
    )
    return future.result()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Detect new DfE dataset versions")
    parser.add_argument("--dataset-id", default=APPRENTICESHIPS_DATASET_ID)
    parser.add_argument("--state-bucket", required=True)
    parser.add_argument("--project")
    parser.add_argument("--topic", help="Pub/Sub topic; omit to skip publishing")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    client = DfEStatisticsClient(dataset_id=args.dataset_id)
    latest = client.get_latest_version()
    previous = read_state(args.state_bucket)
    previous_version = previous.get("latest_version") if previous else None

    log.info("latest=%s previous=%s", latest, previous_version)

    if previous_version == latest:
        log.info("no change; nothing to do")
        return EXIT_NO_CHANGE

    payload = {
        "dataset_id": args.dataset_id,
        "latest_version": latest,
        "previous_version": previous_version,
        "detected_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    if args.topic and args.project:
        message_id = publish_event(args.project, args.topic, payload)
        log.info("published message %s to %s", message_id, args.topic)

    # Only advance state after a successful publish, so a failure re-fires.
    write_state(args.state_bucket, payload)
    log.info("new version detected: %s -> %s", previous_version, latest)
    return EXIT_NEW_VERSION


if __name__ == "__main__":
    sys.exit(main())
