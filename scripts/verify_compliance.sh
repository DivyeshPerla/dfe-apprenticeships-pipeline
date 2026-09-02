#!/usr/bin/env bash
#
# Compliance verification for the apprenticeships platform.
#
# Every control is CHECKED against live GCP state, not asserted in a document.
# Run it before a review, before a release, or in CI. Exit 1 if any control
# fails, so it can gate a pipeline.
#
#   ./scripts/verify_compliance.sh
#
set -uo pipefail

PROJECT="${PROJECT:-dfe-apprenticeships-2026}"
REGION="${REGION:-europe-west2}"
PREFIX="${PREFIX:-dfe-appr}"

PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '        %s\n' "$1"; }

echo "Compliance verification — project ${PROJECT}"
echo "================================================================"

# --- C1 Data residency ------------------------------------------------------
echo
echo "C1  Data residency (UK / ${REGION})"
offending=$(gcloud storage buckets list --project="$PROJECT" \
    --format="value(name,location)" 2>/dev/null \
    | awk -v r="$(echo "$REGION" | tr '[:lower:]' '[:upper:]')" '$2 != r {print $1" ("$2")"}')
if [[ -z "$offending" ]]; then
  ok "all GCS buckets in ${REGION}"
else
  bad "bucket(s) outside ${REGION}: ${offending}"
  note "Cloud Build auto-creates <project>_cloudbuild in the US unless"
  note "deploy passes --gcs-source-staging-dir. See scripts/deploy.sh."
fi

for ds in bronze silver gold; do
  loc=$(bq --project_id="$PROJECT" show --format=prettyjson "$ds" 2>/dev/null \
        | python3 -c "import json,sys;print(json.load(sys.stdin)['location'])" 2>/dev/null)
  [[ "$loc" == "$REGION" ]] && ok "BigQuery dataset ${ds} in ${loc}" \
                            || bad "BigQuery dataset ${ds} in ${loc:-unknown}"
done

# --- C2 Public exposure -----------------------------------------------------
echo
echo "C2  Public access prevention"
for b in bronze artifacts build-staging; do
  bucket="${PREFIX}-${b}-${PROJECT}"
  pap=$(gcloud storage buckets describe "gs://${bucket}" \
        --format="value(public_access_prevention)" 2>/dev/null)
  [[ "$pap" == "enforced" ]] && ok "${b}: enforced" || bad "${b}: ${pap:-not set}"
done

# --- C3 Credential hygiene --------------------------------------------------
echo
echo "C3  Keyless service accounts"
for sa in ingestion transform orchestrator; do
  n=$(gcloud iam service-accounts keys list \
      --iam-account="${PREFIX}-${sa}@${PROJECT}.iam.gserviceaccount.com" \
      --managed-by=user --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$n" == "0" ]] && ok "${sa}: no downloadable keys" \
                    || bad "${sa}: ${n} user-managed key(s) — rotate and remove"
done

# --- C4 Least privilege -----------------------------------------------------
echo
echo "C4  Least privilege (no broad roles on service accounts)"
broad=$(gcloud projects get-iam-policy "$PROJECT" \
        --flatten="bindings[].members" \
        --format="value(bindings.role,bindings.members)" 2>/dev/null \
        | awk '$1 ~ /roles\/(owner|editor)$/ && $2 ~ /serviceAccount:/ {print $2" has "$1}')
if [[ -z "$broad" ]]; then
  ok "no service account holds owner or editor"
else
  bad "over-privileged: ${broad}"
  note "GCP grants the DEFAULT COMPUTE SA roles/editor at project creation."
  note "Cloud Build uses it, so stripping the role breaks the build. Correct"
  note "remediation is a dedicated build SA with least privilege --"
  note "see google_service_account.build in terraform/compute.tf."
fi

# --- C5 Retention -----------------------------------------------------------
echo
echo "C5  Retention lifecycle"
for b in bronze build-staging; do
  rules=$(gcloud storage buckets describe "gs://${PREFIX}-${b}-${PROJECT}" \
          --format="value(lifecycle_config)" 2>/dev/null)
  [[ -n "$rules" && "$rules" != "None" ]] && ok "${b}: lifecycle rules configured" \
                                          || bad "${b}: no lifecycle policy"
done

# --- C6 No personal data ----------------------------------------------------
echo
echo "C6  No personal data in the warehouse"
# UK GDPR scope check: the source is aggregate official statistics. Assert that
# no column name suggests an identifier, so a future schema change that
# introduced one would fail this gate.
pii=$(bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv \
  "SELECT STRING_AGG(DISTINCT column_name) FROM \`${PROJECT}\`.gold.INFORMATION_SCHEMA.COLUMNS
   WHERE REGEXP_CONTAINS(LOWER(column_name),
     r'(email|phone|postcode|address|dob|birth|name_first|surname|nino|ni_number|learner|uln|urn)')" \
  2>/dev/null | tail -1 | tr -d '"' | tr -d '[:space:]')
if [[ -z "$pii" ]]; then
  ok "no identifier-shaped columns in gold"
  note "Source is aggregate statistics; smallest published cell is 10."
else
  bad "possible identifier columns: ${pii}"
fi

# --- C7 Disclosure control preserved ----------------------------------------
echo
echo "C7  Statistical disclosure control preserved end to end"
unrec=$(bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) FROM \`${PROJECT}.gold.fct_apprenticeship_headline\`
   WHERE start_count_status = 'unrecognised'
      OR achievement_count_status = 'unrecognised'" 2>/dev/null | tail -1)
[[ "$unrec" == "0" ]] && ok "no unrecognised suppression markers (${unrec})" \
                      || bad "${unrec} rows carry an unrecognised marker — investigate before publishing"

zeroed=$(bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) FROM \`${PROJECT}.gold.fct_apprenticeship_headline\`
   WHERE start_count_status != 'published' AND start_count IS NOT NULL" 2>/dev/null | tail -1)
[[ "$zeroed" == "0" ]] && ok "no suppressed figure carries a value (${zeroed})" \
                       || bad "${zeroed} suppressed rows have a non-null value — disclosure risk"

# --- C8 Audit trail ---------------------------------------------------------
echo
echo "C8  Audit trail"
# NOTE: `--format="value(versioning.enabled)"` renders empty even when
# versioning IS on. Read the JSON representation instead.
versioning=$(gcloud storage buckets describe "gs://${PREFIX}-bronze-${PROJECT}" \
             --format=json 2>/dev/null \
             | python3 -c "import json,sys;print(json.load(sys.stdin).get('versioning_enabled', False))" 2>/dev/null)
[[ "$versioning" == "True" ]] && ok "bronze object versioning enabled (raw data immutable)" \
                             || bad "bronze versioning off — raw history not protected"

versions=$(bq --project_id="$PROJECT" query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(DISTINCT valid_from_version) FROM \`${PROJECT}.gold.fct_apprenticeship_headline\`" \
  2>/dev/null | tail -1)
[[ "${versions:-0}" -ge 2 ]] && ok "SCD-2 lineage retains ${versions} source versions" \
                             || bad "no version history retained"

echo
echo "================================================================"
echo "  ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]] || exit 1
