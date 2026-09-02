# ---------------------------------------------------------------------------
# Pipeline observability, defined as code alongside the pipeline it watches.
#
# Split deliberately by what each tool is good at:
#   * Cloud Monitoring (here)      -- did it RUN? executions, failures, duration
#   * gold.mart_pipeline_health    -- did it produce GOOD DATA? freshness,
#                                     volume, suppression drift, reconciliation
#
# A pipeline that runs green while silently loading wrong data is the failure
# mode that matters, so both halves are needed.
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "pipeline" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "Apprenticeships pipeline"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width = 6, height = 4, xPos = 0, yPos = 0
          widget = {
            title = "Workflow executions by outcome"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"workflows.googleapis.com/finished_execution_count\"",
                      "resource.type=\"workflows.googleapis.com/Workflow\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.label.status"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = { label = "executions", scale = "LINEAR" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 0
          widget = {
            title = "Cloud Run job completions by result"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"run.googleapis.com/job/completed_execution_count\"",
                      "resource.type=\"cloud_run_job\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.job_name", "metric.label.result"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = { label = "completions", scale = "LINEAR" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 0, yPos = 4
          widget = {
            title = "Job task runtime (95th percentile)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"run.googleapis.com/job/completed_task_attempt_count\"",
                      "resource.type=\"cloud_run_job\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.job_name"]
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = { label = "task attempts", scale = "LINEAR" }
            }
          }
        },
        {
          width = 6, height = 4, xPos = 6, yPos = 4
          widget = {
            title = "Errors in pipeline logs"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = join(" AND ", [
                      "metric.type=\"logging.googleapis.com/log_entry_count\"",
                      "resource.type=\"cloud_run_job\"",
                      "metric.label.severity=\"ERROR\"",
                    ])
                    aggregation = {
                      alignmentPeriod    = "3600s"
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.job_name"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
              yAxis = { label = "log entries", scale = "LINEAR" }
            }
          }
        },
      ]
    }
  })

  depends_on = [google_project_service.required]
}

# ---------------------------------------------------------------------------
# Alerting. One policy, deliberately: a pipeline this quiet should page on the
# thing that actually matters -- the transform failing, which means gold is
# stale or wrong. Extract failures are retried and self-heal on the next run.
# ---------------------------------------------------------------------------

resource "google_monitoring_alert_policy" "transform_failed" {
  project      = var.project_id
  display_name = "Apprenticeships transform job failed"
  combiner     = "OR"

  documentation {
    content = join("\n", [
      "The dbt transform job failed, so silver and gold are stale or partially built.",
      "",
      "Check: gcloud logging read 'resource.labels.job_name=\"${var.resource_prefix}-transform\"' --limit=50",
      "A dbt test failure is the most common cause and is usually a real data problem, not a flake.",
    ])
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "transform job failed in the last hour"
    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/job/completed_execution_count\"",
        "resource.type=\"cloud_run_job\"",
        "resource.label.job_name=\"${var.resource_prefix}-transform\"",
        "metric.label.result=\"failed\"",
      ])
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "3600s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  # Auto-close if nothing recurs, so a one-off failure does not linger open.
  alert_strategy {
    auto_close = "604800s"
  }

  depends_on = [google_project_service.required]
}
