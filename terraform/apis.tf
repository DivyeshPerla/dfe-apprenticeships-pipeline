# Services required across all phases. Enabled up front so later phases do not
# fail on a cold API. `disable_on_destroy = false` avoids tearing down APIs that
# other things in the project may depend on.
locals {
  required_apis = [
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "workflows.googleapis.com",
    "workflowexecutions.googleapis.com",
    "secretmanager.googleapis.com",
    "aiplatform.googleapis.com",
    "dataplex.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
  ]
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
