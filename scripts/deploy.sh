#!/usr/bin/env bash
#
# Build the ingestion image, push it to Artifact Registry, and apply the
# infrastructure that depends on it.
#
# Ordering matters: Cloud Run Jobs cannot be created against an image that
# does not exist yet, so the registry is applied first, then the image is
# built, then the jobs.
set -euo pipefail

PROJECT="${PROJECT:-dfe-apprenticeships-2026}"
REGION="${REGION:-europe-west2}"
PREFIX="${PREFIX:-dfe-appr}"
TAG="${TAG:-$(git rev-parse --short HEAD)}"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${PREFIX}/pipeline:${TAG}"

cd "$(dirname "$0")/.."

echo "==> 1/3 provisioning registry, topic and identities"
terraform -chdir=terraform apply -auto-approve \
  -target=google_artifact_registry_repository.images \
  -target=google_pubsub_topic.version_published \
  -target=google_service_account.orchestrator \
  -var="image_tag=${TAG}"

echo "==> 2/3 building ${IMAGE}"
# Cloud Build keeps this inside the free tier and avoids needing a local
# Docker daemon.
gcloud builds submit \
  --project="${PROJECT}" \
  --region="${REGION}" \
  --tag="${IMAGE}" \
  .

echo "==> 3/3 applying remaining infrastructure"
terraform -chdir=terraform apply -auto-approve -var="image_tag=${TAG}"

echo
echo "Deployed image tag: ${TAG}"
echo "Trigger a run with:"
echo "  gcloud workflows run ${PREFIX}-pipeline --location=${REGION} --project=${PROJECT}"
