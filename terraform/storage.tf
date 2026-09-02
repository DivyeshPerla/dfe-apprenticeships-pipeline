# ---------------------------------------------------------------------------
# Bronze: immutable raw landing zone.
# Layout: apprenticeships/version=<X>/ingest_date=<YYYY-MM-DD>/{data.csv,meta.json,_manifest.json}
# Versioning is ON because replayability is the whole point of this layer.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "bronze" {
  name     = "${var.resource_prefix}-bronze-${var.project_id}"
  location = var.region
  project  = var.project_id
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  # Raw source files are tiny (~8 MB/version); cool them rather than delete.
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  depends_on = [google_project_service.required]
}

# Build artifacts, dbt docs, exports. Safe to lose; not versioned.
resource "google_storage_bucket" "artifacts" {
  name     = "${var.resource_prefix}-artifacts-${var.project_id}"
  location = var.region
  project  = var.project_id
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Cloud Build source staging.
#
# COMPLIANCE CONTROL: left to itself, `gcloud builds submit` auto-creates
# <project>_cloudbuild in the US and stages every source tarball there. For a
# UK data-residency claim that is a real gap -- source and dbt seeds leave the
# region. This bucket pins staging to europe-west2; scripts/deploy.sh passes it
# via --gcs-source-staging-dir.
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "build_staging" {
  name     = "${var.resource_prefix}-build-staging-${var.project_id}"
  location = var.region
  project  = var.project_id
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Build sources are reproducible from git; keep the window short.
  lifecycle_rule {
    condition {
      age = 14
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required]
}
