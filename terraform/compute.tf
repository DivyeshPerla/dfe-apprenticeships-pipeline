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
