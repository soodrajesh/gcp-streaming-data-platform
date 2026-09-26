# events (Avro-validated) ──► [BigQuery subscription] ──► raw.events          (append-only landing)
#                        └──► [push subscription] ──► Cloud Run enricher ──► curated.orders
#                                   │ 5 failed deliveries
#                                   ▼
#                              events-dlq ──► [BigQuery subscription] ──► raw.dead_letters

resource "google_pubsub_schema" "order_event" {
  project    = var.project_id
  name       = "order-event"
  type       = "AVRO"
  definition = file("${path.module}/../app/order_event.avsc")
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic" "events" {
  project = var.project_id
  name    = "events"
  schema_settings {
    schema   = google_pubsub_schema.order_event.id
    encoding = "JSON"
  }
  message_retention_duration = "86400s"
  depends_on                 = [google_pubsub_schema.order_event]
}

resource "google_pubsub_topic" "dlq" {
  project    = var.project_id
  name       = "events-dlq"
  depends_on = [google_project_service.apis]
}

# ── IAM for the Pub/Sub service agent ─────────────────────────────────────────────────────────────
resource "google_bigquery_dataset_iam_member" "agent_raw" {
  for_each   = toset(["roles/bigquery.dataEditor", "roles/bigquery.metadataViewer"])
  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = each.value
  member     = local.pubsub_agent
}

resource "google_pubsub_topic_iam_member" "agent_publish_dlq" {
  project = var.project_id
  topic   = google_pubsub_topic.dlq.name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_agent
}

resource "google_pubsub_subscription_iam_member" "agent_ack" {
  count        = var.image == "" ? 0 : 1
  project      = var.project_id
  subscription = google_pubsub_subscription.enrich[0].name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}

resource "google_service_account_iam_member" "agent_mint_oidc" {
  service_account_id = google_service_account.sa["sdp-push"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.pubsub_agent
}

# ── subscriptions ─────────────────────────────────────────────────────────────────────────────────
resource "google_pubsub_subscription" "to_bq" {
  project = var.project_id
  name    = "events-to-bq"
  topic   = google_pubsub_topic.events.id

  bigquery_config {
    table               = "${var.project_id}.${google_bigquery_dataset.raw.dataset_id}.${google_bigquery_table.raw_events.table_id}"
    use_topic_schema    = true
    write_metadata      = true
    drop_unknown_fields = true
  }
  depends_on = [google_bigquery_dataset_iam_member.agent_raw]
}

resource "google_pubsub_subscription" "dlq_to_bq" {
  project = var.project_id
  name    = "events-dlq-to-bq"
  topic   = google_pubsub_topic.dlq.id

  bigquery_config {
    table          = "${var.project_id}.${google_bigquery_dataset.raw.dataset_id}.${google_bigquery_table.dead_letters.table_id}"
    write_metadata = true
  }
  depends_on = [google_bigquery_dataset_iam_member.agent_raw]
}

resource "google_pubsub_subscription" "enrich" {
  count   = var.image == "" ? 0 : 1
  project = var.project_id
  name    = "events-to-enricher"
  topic   = google_pubsub_topic.events.id

  ack_deadline_seconds = 30
  push_config {
    push_endpoint = google_cloud_run_v2_service.enricher[0].uri
    oidc_token {
      service_account_email = google_service_account.sa["sdp-push"].email
      audience              = google_cloud_run_v2_service.enricher[0].uri
    }
  }
  retry_policy {
    minimum_backoff = "5s"
    maximum_backoff = "20s"
  }
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = 5
  }
  depends_on = [google_pubsub_topic_iam_member.agent_publish_dlq, google_service_account_iam_member.agent_mint_oidc]
}

# generator: publisher on the events topic only
resource "google_pubsub_topic_iam_member" "generator_publish" {
  project = var.project_id
  topic   = google_pubsub_topic.events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.sa["sdp-generator"].email}"
}
