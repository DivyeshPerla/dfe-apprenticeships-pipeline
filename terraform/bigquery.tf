# Medallion layers as separate datasets so IAM can differ per layer:
# bronze = raw as-loaded, silver = typed/cleaned, gold = star schema + marts.
locals {
  datasets = {
    bronze = "Raw as-loaded source data. No transformation. Replayable from GCS."
    silver = "Typed and cleaned. Suppression codes split from values."
    gold   = "Dimensional model (star schema) and analytics marts."
  }
}

resource "google_bigquery_dataset" "layers" {
  for_each = local.datasets

  dataset_id    = each.key
  project       = var.project_id
  location      = var.bq_location
  friendly_name = "${title(each.key)} layer"
  description   = each.value
  labels        = var.labels

  # Guardrail: this project is a case study, not production. Prevents an
  # accidental `terraform destroy` from silently dropping populated tables.
  delete_contents_on_destroy = false

  depends_on = [google_project_service.required]
}
