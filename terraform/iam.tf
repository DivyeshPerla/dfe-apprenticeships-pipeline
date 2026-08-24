# ---------------------------------------------------------------------------
# Least-privilege service accounts. Scoped at bucket/dataset level rather than
# project level so the ingestion identity cannot read or write the gold marts.
# ---------------------------------------------------------------------------

resource "google_service_account" "ingestion" {
  account_id   = "${var.resource_prefix}-ingestion"
  display_name = "DfE apprenticeships ingestion (Cloud Run Job)"
  project      = var.project_id
  depends_on   = [google_project_service.required]
}

resource "google_service_account" "transform" {
  account_id   = "${var.resource_prefix}-transform"
  display_name = "DfE apprenticeships transform (dbt)"
  project      = var.project_id
  depends_on   = [google_project_service.required]
}

# -- ingestion: write raw to bronze bucket, load into bronze dataset ---------

resource "google_storage_bucket_iam_member" "ingestion_bronze_writer" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.ingestion.member
}

resource "google_bigquery_dataset_iam_member" "ingestion_bronze_editor" {
  dataset_id = google_bigquery_dataset.layers["bronze"].dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.ingestion.member
}

# Running a load job is a project-level permission; dataEditor alone is not
# enough. jobUser is the minimum that allows it.
resource "google_project_iam_member" "ingestion_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.ingestion.member
}

# -- transform: read bronze, own silver and gold ----------------------------

resource "google_storage_bucket_iam_member" "transform_bronze_reader" {
  bucket = google_storage_bucket.bronze.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.transform.member
}

resource "google_bigquery_dataset_iam_member" "transform_bronze_viewer" {
  dataset_id = google_bigquery_dataset.layers["bronze"].dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.transform.member
}

resource "google_bigquery_dataset_iam_member" "transform_editor" {
  for_each = toset(["silver", "gold"])

  dataset_id = google_bigquery_dataset.layers[each.value].dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.transform.member
}

resource "google_project_iam_member" "transform_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.transform.member
}
