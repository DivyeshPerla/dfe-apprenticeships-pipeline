#!/usr/bin/env bash
# Recreate the bronze external table over the GCS landing zone.
#
# Hive partitioning (mode AUTO) derives `version` and `ingest_date` as real
# queryable columns straight from the object path -- no ingestion code needed.
# Note BigQuery permits only ONE wildcard per source URI, which is why data
# files and JSON sidecars live under separate prefixes (see src/ingestion/gcs.py).
set -euo pipefail

PROJECT="${PROJECT:-dfe-apprenticeships-2026}"
BUCKET="${BUCKET:-dfe-appr-bronze-dfe-apprenticeships-2026}"
BASE="gs://${BUCKET}/apprenticeships/data"

python3 - "$BASE" > /tmp/extdef.json <<'PY'
import json, sys
base = sys.argv[1]
cols = ["time_period","time_identifier","geographic_level","country_code","country_name",
        "region_code","region_name","apprenticeship_level","age_youth_adult","age_group",
        "funding_type","provider_type","start_count","achievement_count",
        "participation_count","starts_percent","achievements_percent"]
json.dump({
  "sourceFormat": "CSV",
  "sourceUris": [f"{base}/*"],
  "csvOptions": {"skipLeadingRows": 1, "quote": '"', "allowQuotedNewlines": True},
  # Bronze principle: everything lands as STRING. Suppression markers live in
  # the numeric columns; a typed load here would silently null them.
  "schema": {"fields": [{"name": c, "type": "STRING"} for c in cols]},
  "hivePartitioningOptions": {"mode": "AUTO", "sourceUriPrefix": base},
}, sys.stdout, indent=2)
PY

bq --project_id="$PROJECT" rm -f -t "${PROJECT}:bronze.raw_apprenticeships"
bq --project_id="$PROJECT" mk --table \
  --external_table_definition=/tmp/extdef.json \
  "${PROJECT}:bronze.raw_apprenticeships"
echo "created ${PROJECT}:bronze.raw_apprenticeships"
