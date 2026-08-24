"""Extraction entrypoint: DfE API -> local path or GCS bronze layer.

Bronze layout (immutable, replayable):
    bronze/apprenticeships/version=<X>/ingest_date=<YYYY-MM-DD>/data.csv
                                                               /meta.json
                                                               /_manifest.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import logging
import os
import sys
import tempfile

from ingestion.dfe_client import APPRENTICESHIPS_DATASET_ID, DfEStatisticsClient

log = logging.getLogger(__name__)


def _sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_version(
    client: DfEStatisticsClient, version: str, out_dir: str
) -> dict:
    """Download one version's CSV + meta and write a reconciliation manifest."""
    os.makedirs(out_dir, exist_ok=True)
    csv_path = os.path.join(out_dir, "data.csv")
    meta_path = os.path.join(out_dir, "meta.json")

    client.download_csv(csv_path, version=version)
    with open(meta_path, "w") as fh:
        json.dump(client.get_meta(), fh, indent=2)

    with open(csv_path) as fh:
        row_count = sum(1 for _ in fh) - 1  # minus header

    manifest = {
        "dataset_id": client.dataset_id,
        "dataset_version": version,
        "ingested_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "row_count": row_count,
        "bytes": os.path.getsize(csv_path),
        "sha256": _sha256(csv_path),
    }
    with open(os.path.join(out_dir, "_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)

    log.info("extracted version=%s rows=%s -> %s", version, row_count, out_dir)
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Extract DfE apprenticeships data")
    parser.add_argument("--dataset-id", default=APPRENTICESHIPS_DATASET_ID)
    parser.add_argument(
        "--version", help="dataset version, e.g. 2.0.2 (default: latest)"
    )
    parser.add_argument(
        "--all-versions",
        action="store_true",
        help="backfill every published version",
    )
    parser.add_argument("--list-versions", action="store_true")
    parser.add_argument("--out", default="data/bronze/apprenticeships")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    client = DfEStatisticsClient(dataset_id=args.dataset_id)

    if args.list_versions:
        for v in client.list_versions():
            print(
                f"{v.version:<7} {v.type:<6} {v.published[:10]}  "
                f"rows={v.total_results:>6}  {v.time_period_start}..{v.time_period_end}"
            )
        return 0

    today = dt.date.today().isoformat()
    versions = (
        [v.version for v in client.list_versions()]
        if args.all_versions
        else [args.version or client.get_latest_version()]
    )

    for version in versions:
        out_dir = os.path.join(args.out, f"version={version}", f"ingest_date={today}")
        extract_version(client, version, out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
