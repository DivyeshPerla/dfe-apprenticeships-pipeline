variable "project_id" {
  description = "Existing GCP project id. Create the project and link billing first."
  type        = string
}

variable "region" {
  description = "Primary region. europe-west2 (London) keeps UK public data in-region."
  type        = string
  default     = "europe-west2"
}

variable "bq_location" {
  description = "BigQuery dataset location. Must be compatible with var.region."
  type        = string
  default     = "europe-west2"
}

variable "resource_prefix" {
  description = "Prefix for globally-unique resource names (buckets, etc)."
  type        = string
  default     = "dfe-appr"
}

variable "labels" {
  description = "Labels applied to billable resources, for cost attribution."
  type        = map(string)
  default = {
    project = "dfe-apprenticeships"
    env     = "dev"
    managed = "terraform"
  }
}
