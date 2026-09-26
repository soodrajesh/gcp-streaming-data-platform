resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Streaming platform alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
  depends_on   = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "backlog" {
  project      = var.project_id
  display_name = "Streaming: events are not being consumed (oldest unacked > 5 min)"
  combiner     = "OR"
  conditions {
    display_name = "oldest unacked message age > 300 s"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" AND resource.type=\"pubsub_subscription\""
      comparison      = "COMPARISON_GT"
      threshold_value = 300
      duration        = "120s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content   = "A subscription is falling behind. Runbook: docs/runbooks/05-incident-response.md"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "poison" {
  project      = var.project_id
  display_name = "Streaming: poison events reached the dead-letter topic"
  combiner     = "OR"
  conditions {
    display_name = "any message published to events-dlq"
    condition_threshold {
      filter          = "metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\" AND resource.type=\"pubsub_topic\" AND resource.label.topic_id=\"${google_pubsub_topic.dlq.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content   = "Events failed validation 5 times. Inspect raw.dead_letters. Runbook: docs/runbooks/04-dead-letters.md"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_dashboard" "main" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Streaming data platform"
    mosaicLayout = {
      columns = 12
      tiles = [
        { width = 6, height = 4, widget = { title = "Messages published to events (per min)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\" resource.type=\"pubsub_topic\" resource.label.topic_id=\"events\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE" } } } }] } } },
        { xPos = 6, width = 6, height = 4, widget = { title = "Oldest unacked message age (s)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\" resource.type=\"pubsub_subscription\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_MAX", groupByFields = ["resource.label.subscription_id"], crossSeriesReducer = "REDUCE_MAX" } } } }] } } },
        { yPos = 4, width = 6, height = 4, widget = { title = "Dead-lettered messages (5 min)", xyChart = { dataSets = [{ plotType = "STACKED_BAR", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"pubsub.googleapis.com/topic/send_message_operation_count\" resource.type=\"pubsub_topic\" resource.label.topic_id=\"events-dlq\"", aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM" } } } }] } } },
        { xPos = 6, yPos = 4, width = 6, height = 4, widget = { title = "Enricher request latency (p95, ms)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"enricher\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95", crossSeriesReducer = "REDUCE_MAX" } } } }] } } },
      ]
    }
  })
  depends_on = [google_project_service.apis]
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "streaming-data-platform"
  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(var.budget_amount)
    }
  }
  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 1.0 }
  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }
  depends_on = [google_project_service.apis]
}
