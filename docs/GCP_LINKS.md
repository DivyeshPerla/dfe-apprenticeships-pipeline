# GCP console links

Project: **dfe-apprenticeships-2026** (number 896157154507), region **europe-west2**
Sign in as **divyeshperla@gmail.com** — the account that owns these resources.

## Overview
- [Project dashboard](https://console.cloud.google.com/home/dashboard?project=dfe-apprenticeships-2026)
- [All Terraform-managed resources (asset inventory)](https://console.cloud.google.com/iam-admin/asset-inventory/dashboard?project=dfe-apprenticeships-2026)

## The pipeline
- [**Workflow executions**](https://console.cloud.google.com/workflows/workflow/europe-west2/dfe-appr-pipeline/executions?project=dfe-apprenticeships-2026) — the execution graph; best single screenshot
- [Workflow definition](https://console.cloud.google.com/workflows/workflow/europe-west2/dfe-appr-pipeline/definition?project=dfe-apprenticeships-2026)
- [Cloud Run jobs](https://console.cloud.google.com/run/jobs?project=dfe-apprenticeships-2026) — extract, transform, version-watcher
- [Cloud Scheduler](https://console.cloud.google.com/cloudscheduler?project=dfe-apprenticeships-2026) — daily 07:00 Europe/London
- [Pub/Sub topic](https://console.cloud.google.com/cloudpubsub/topic/list?project=dfe-apprenticeships-2026)

## Data
- [**BigQuery**](https://console.cloud.google.com/bigquery?project=dfe-apprenticeships-2026) — bronze / silver / gold
- [GCS buckets](https://console.cloud.google.com/storage/browser?project=dfe-apprenticeships-2026)
- [Bronze landing zone](https://console.cloud.google.com/storage/browser/dfe-appr-bronze-dfe-apprenticeships-2026/apprenticeships?project=dfe-apprenticeships-2026) — hive-partitioned by version
- [Artifact Registry](https://console.cloud.google.com/artifacts/docker/dfe-apprenticeships-2026/europe-west2/dfe-appr?project=dfe-apprenticeships-2026)

## AI
- [BQML models](https://console.cloud.google.com/bigquery?project=dfe-apprenticeships-2026&ws=!1m4!1m3!3m2!1sdfe-apprenticeships-2026!2sgold) — region_segments (k-means), gemini (remote)

## Operations
- [Cloud Build history](https://console.cloud.google.com/cloud-build/builds?project=dfe-apprenticeships-2026)
- [Logs](https://console.cloud.google.com/logs/query?project=dfe-apprenticeships-2026)
- [Budget $25 with 50/90/100% alerts](https://console.cloud.google.com/billing/01B8D5-AA119B-D2F10F/budgets)
- [Current spend](https://console.cloud.google.com/billing/01B8D5-AA119B-D2F10F/reports?project=dfe-apprenticeships-2026)

## dbt docs
Published to `gs://dfe-appr-artifacts-dfe-apprenticeships-2026/dbt-docs/index.html`, but the bucket
enforces public access prevention, so there is no shareable URL. Open the local
copy instead:

```bash
open ~/dev/dfe-apprenticeships-pipeline/dbt/target/index.html
```
