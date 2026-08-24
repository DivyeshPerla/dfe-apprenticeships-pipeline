variable "image_tag" {
  description = "Container image tag to deploy. Set by scripts/deploy.sh."
  type        = string
  default     = "latest"
}

locals {
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.resource_prefix}/pipeline:${var.image_tag}"
}

# -- extract job ------------------------------------------------------------

resource "google_cloud_run_v2_job" "extract" {
  name     = "${var.resource_prefix}-extract"
  project  = var.project_id
  location = var.region
  labels   = var.labels

  deletion_protection = false

  template {
    template {
      service_account = google_service_account.ingestion.email
      # Generous: a full six-version backfill takes ~2 minutes.
      timeout     = "900s"
      max_retries = 1

      containers {
        image   = local.image
        command = ["python"]
        args = [
          "-m", "ingestion.extract",
          "--gcs-bucket", google_storage_bucket.bronze.name,
        ]
        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

# -- version watcher job ----------------------------------------------------

resource "google_cloud_run_v2_job" "version_watcher" {
  name     = "${var.resource_prefix}-version-watcher"
  project  = var.project_id
  location = var.region
  labels   = var.labels

  deletion_protection = false

  template {
    template {
      service_account = google_service_account.ingestion.email
      timeout         = "300s"
      max_retries     = 1

      containers {
        image   = local.image
        command = ["python"]
        args = [
          "-m", "ingestion.version_watcher",
          "--state-bucket", google_storage_bucket.bronze.name,
          "--project", var.project_id,
          "--topic", google_pubsub_topic.version_published.name,
        ]
        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

# -- workflow ---------------------------------------------------------------

resource "google_workflows_workflow" "pipeline" {
  name            = "${var.resource_prefix}-pipeline"
  project         = var.project_id
  region          = var.region
  description     = "Poll for a new dataset version; extract only when one exists"
  service_account = google_service_account.orchestrator.id
  labels          = var.labels

  source_contents = file("${path.module}/../workflows/pipeline.yaml")

  depends_on = [google_project_service.required]
}

# -- schedule ---------------------------------------------------------------

resource "google_cloud_scheduler_job" "daily" {
  name        = "${var.resource_prefix}-daily"
  project     = var.project_id
  region      = var.region
  description = "Daily check for a newly published dataset version"
  # Source publishes ~quarterly; daily polling is cheap and well inside the
  # 3-job always-free Scheduler allowance.
  schedule  = "0 7 * * *"
  time_zone = "Europe/London"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/${google_workflows_workflow.pipeline.id}/executions"

    oauth_token {
      service_account_email = google_service_account.orchestrator.email
    }
  }

  depends_on = [google_project_service.required]
}

# -- transform job ----------------------------------------------------------
#
# Runs the dbt build (models + tests) inside GCP. Without this the pipeline
# would land new data in bronze and leave silver/gold stale until someone ran
# dbt by hand -- i.e. not a pipeline at all.
#
# Uses the transform identity, which can read bronze and own silver/gold but
# cannot write to the raw landing zone.

resource "google_cloud_run_v2_job" "transform" {
  name     = "${var.resource_prefix}-transform"
  project  = var.project_id
  location = var.region
  labels   = var.labels

  deletion_protection = false

  template {
    template {
      service_account = google_service_account.transform.email
      timeout         = "1800s"
      max_retries     = 0

      containers {
        image   = local.image
        command = ["dbt"]
        # `build` runs models and their tests together, stopping on failure,
        # so a broken transform never publishes to gold.
        args = [
          "build",
          "--project-dir", "/app/dbt",
          "--profiles-dir", "/app/dbt",
          "--target", "dev",
        ]
        resources {
          limits = {
            cpu    = "1"
            memory = "2Gi"
          }
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}
