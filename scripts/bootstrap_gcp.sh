#!/usr/bin/env bash
#
# One-time GCP bootstrap. Run the steps you need; it is safe to re-run.
#
# Prerequisites you must do yourself (they need your Google account):
#   1. gcloud auth login
#   2. a billing account you own -- find it with:  gcloud billing accounts list
#
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-dfe-apprenticeships-$(date +%Y%m%d)}"
PROJECT_NAME="${PROJECT_NAME:-DfE Apprenticeships Platform}"
REGION="${REGION:-europe-west2}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-20}"   # GBP -- deliberately low; raise later

echo "==> project: ${PROJECT_ID}  region: ${REGION}"

# --- 1. project ------------------------------------------------------------
if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "    project already exists, skipping create"
else
  gcloud projects create "${PROJECT_ID}" --name="${PROJECT_NAME}"
fi

gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"

# --- 2. billing ------------------------------------------------------------
# Terraform cannot enable APIs on a project with no billing account linked.
if [[ -z "${BILLING_ACCOUNT}" ]]; then
  echo
  echo "!!! BILLING_ACCOUNT not set. Available accounts:"
  gcloud billing accounts list
  echo
  echo "    Re-run with:  BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX $0"
  exit 1
fi

gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"

# --- 3. budget alert BEFORE any resources ----------------------------------
# Set the guardrail first. Cloud Composer is the one item that can run away.
if ! gcloud billing budgets list --billing-account="${BILLING_ACCOUNT}" \
      --format='value(displayName)' 2>/dev/null | grep -q "^${PROJECT_ID}-budget$"; then
  gcloud billing budgets create \
    --billing-account="${BILLING_ACCOUNT}" \
    --display-name="${PROJECT_ID}-budget" \
    --budget-amount="${BUDGET_AMOUNT}GBP" \
    --threshold-rule=percent=0.5 \
    --threshold-rule=percent=0.9 \
    --threshold-rule=percent=1.0
else
  echo "    budget already exists, skipping"
fi

# --- 4. credentials for Terraform -----------------------------------------
gcloud auth application-default login
gcloud auth application-default set-quota-project "${PROJECT_ID}"

cat <<NEXT

==> Bootstrap complete.

Next:
  cd terraform
  cp terraform.tfvars.example terraform.tfvars
  # set project_id = "${PROJECT_ID}"
  terraform init
  terraform plan
  terraform apply
NEXT
