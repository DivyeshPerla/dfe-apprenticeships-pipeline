output "bronze_bucket" {
  description = "GCS bronze landing bucket."
  value       = google_storage_bucket.bronze.name
}

output "artifacts_bucket" {
  description = "GCS bucket for build artifacts and dbt docs."
  value       = google_storage_bucket.artifacts.name
}

output "bigquery_datasets" {
  description = "Medallion layer dataset ids."
  value       = { for k, ds in google_bigquery_dataset.layers : k => ds.dataset_id }
}

output "ingestion_service_account" {
  description = "Service account email for the ingestion Cloud Run Job."
  value       = google_service_account.ingestion.email
}

output "transform_service_account" {
  description = "Service account email for dbt."
  value       = google_service_account.transform.email
}

output "bronze_uri" {
  description = "Base URI for the raw apprenticeships landing zone."
  value       = "gs://${google_storage_bucket.bronze.name}/apprenticeships"
}

output "build_staging_bucket" {
  description = "In-region Cloud Build source staging bucket (residency control)."
  value       = google_storage_bucket.build_staging.name
}
