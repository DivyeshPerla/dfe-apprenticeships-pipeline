# ---------------------------------------------------------------------------
# Serverless orchestration. Deliberately NOT Cloud Composer: Composer has no
# free tier (~£250-400/month) whereas Cloud Workflows + Cloud Scheduler +
# Cloud Run Jobs all sit inside the always-free allowances at this volume.
# ---------------------------------------------------------------------------

resource "google_artifact_registry_repository" "images" {
  repository_id = var.resource_prefix
  project       = var.project_id
  location      = var.region
  format        = "DOCKER"
  description   = "Container images for the apprenticeships pipeline"
  labels        = var.labels

  # Keep the repo inside the 0.5 GB always-free tier by pruning old images.
  cleanup_policies {
    id     = "keep-recent-only"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }

  depends_on = [google_project_service.required]
}

# -- event topic ------------------------------------------------------------

resource "google_pubsub_topic" "version_published" {
  name    = "${var.resource_prefix}-version-published"
  project = var.project_id
  labels  = var.labels

  depends_on = [google_project_service.required]
}

# -- orchestration ----------------------------------------------------------

resource "google_service_account" "orchestrator" {
  account_id   = "${var.resource_prefix}-orchestrator"
  display_name = "Workflows + Scheduler orchestration identity"
  project      = var.project_id
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "orchestrator_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = google_service_account.orchestrator.member
}

resource "google_project_iam_member" "orchestrator_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = google_service_account.orchestrator.member
}

# The ingestion identity needs to publish version-change events.
resource "google_pubsub_topic_iam_member" "ingestion_publisher" {
  topic   = google_pubsub_topic.version_published.name
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_service_account.ingestion.member
}

# The workflow reads the watcher's decision object to decide whether to extract.
resource "google_storage_bucket_iam_member" "orchestrator_state_reader" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.orchestrator.member
}

# Starting a job needs run.invoker; *waiting* for it needs read access to the
# execution resource as well, otherwise the workflow 403s while polling.
resource "google_project_iam_member" "orchestrator_run_viewer" {
  project = var.project_id
  role    = "roles/run.viewer"
  member  = google_service_account.orchestrator.member
}

# ---------------------------------------------------------------------------
# Dedicated Cloud Build identity.
#
# COMPLIANCE CONTROL (C4): at project creation GCP grants the default compute
# service account roles/editor -- broad write access across the whole project.
# Cloud Build defaults to that identity, so the role cannot simply be stripped
# without breaking builds. This SA holds only what a build actually needs:
# push to Artifact Registry, read staged source, write its own logs.
# ---------------------------------------------------------------------------

resource "google_service_account" "build" {
  account_id   = "${var.resource_prefix}-build"
  display_name = "Cloud Build (least privilege)"
  project      = var.project_id
  depends_on   = [google_project_service.required]
}

resource "google_artifact_registry_repository_iam_member" "build_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.build.member
}

resource "google_storage_bucket_iam_member" "build_source_reader" {
  bucket = google_storage_bucket.build_staging.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.build.member
}

# Builds submitted with a user-specified SA must be able to write their logs.
resource "google_project_iam_member" "build_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.build.member
}

# Build logs go to our own in-region artifacts bucket rather than the
# auto-created regional logs bucket, so the identity needs write access there.
# Cloud Build requires storage.admin on its log bucket -- objectAdmin is not
# enough, because it also reads bucket metadata. Scoped to this one bucket, so
# it is still far narrower than the project-wide editor it replaces.
resource "google_storage_bucket_iam_member" "build_log_bucket" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.admin"
  member = google_service_account.build.member
}
