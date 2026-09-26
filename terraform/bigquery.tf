resource "google_bigquery_dataset" "raw" {
  project                    = var.project_id
  dataset_id                 = "raw"
  location                   = var.bq_location
  description                = "Append-only landing zone. Not readable by analysts."
  delete_contents_on_destroy = true
  depends_on                 = [google_project_service.apis]
}

resource "google_bigquery_dataset" "curated" {
  project                    = var.project_id
  dataset_id                 = "curated"
  location                   = var.bq_location
  description                = "Validated, enriched orders. Contains PII (email); not readable by analysts."
  delete_contents_on_destroy = true
  depends_on                 = [google_project_service.apis]
}

resource "google_bigquery_dataset" "mart" {
  project                    = var.project_id
  dataset_id                 = "mart"
  location                   = var.bq_location
  description                = "Analyst-facing, PII-masked authorized views."
  delete_contents_on_destroy = true
  depends_on                 = [google_project_service.apis]
}

resource "google_bigquery_table" "raw_events" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "events"
  deletion_protection = false
  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }
  schema = jsonencode([
    { name = "event_id", type = "STRING", mode = "REQUIRED" },
    { name = "order_id", type = "STRING", mode = "REQUIRED" },
    { name = "customer_email", type = "STRING", mode = "REQUIRED" },
    { name = "amount", type = "FLOAT", mode = "REQUIRED" },
    { name = "currency", type = "STRING", mode = "REQUIRED" },
    { name = "event_time", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "subscription_name", type = "STRING", mode = "NULLABLE" },
    { name = "message_id", type = "STRING", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "attributes", type = "STRING", mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "dead_letters" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.raw.dataset_id
  table_id            = "dead_letters"
  deletion_protection = false
  time_partitioning {
    type  = "DAY"
    field = "publish_time"
  }
  schema = jsonencode([
    { name = "data", type = "STRING", mode = "NULLABLE" },
    { name = "subscription_name", type = "STRING", mode = "NULLABLE" },
    { name = "message_id", type = "STRING", mode = "NULLABLE" },
    { name = "publish_time", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "attributes", type = "STRING", mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "orders" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.curated.dataset_id
  table_id            = "orders"
  deletion_protection = false
  time_partitioning {
    type  = "DAY"
    field = "event_time"
  }
  schema = jsonencode([
    { name = "event_id", type = "STRING", mode = "REQUIRED" },
    { name = "order_id", type = "STRING", mode = "REQUIRED" },
    { name = "customer_email", type = "STRING", mode = "REQUIRED" },
    { name = "amount", type = "FLOAT", mode = "REQUIRED" },
    { name = "currency", type = "STRING", mode = "REQUIRED" },
    { name = "event_time", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "amount_eur", type = "FLOAT", mode = "REQUIRED" },
    { name = "fx_rate", type = "FLOAT", mode = "REQUIRED" },
    { name = "enriched_at", type = "TIMESTAMP", mode = "REQUIRED" },
  ])
}

# Exactly-once at READ time: streaming inserts and redeliveries are at-least-once, so the mart de-duplicates.
resource "google_bigquery_table" "orders_masked" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.mart.dataset_id
  table_id            = "orders_masked"
  deletion_protection = false
  view {
    use_legacy_sql = false
    query          = <<-SQL
      SELECT event_id, order_id,
             SUBSTR(TO_HEX(SHA256(LOWER(customer_email))), 1, 12) AS customer_key,
             amount, currency, amount_eur, event_time
      FROM `${var.project_id}.curated.orders`
      QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY enriched_at DESC) = 1
    SQL
  }
  depends_on = [google_bigquery_table.orders]
}

resource "google_bigquery_table" "orders_per_minute_mv" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.curated.dataset_id
  table_id            = "orders_per_minute_mv"
  deletion_protection = false
  materialized_view {
    enable_refresh      = true
    refresh_interval_ms = 60000
    query               = <<-SQL
      SELECT TIMESTAMP_TRUNC(event_time, MINUTE) AS minute, currency,
             COUNT(*) AS orders, SUM(amount_eur) AS revenue_eur
      FROM `${var.project_id}.curated.orders`
      GROUP BY minute, currency
    SQL
  }
  depends_on = [google_bigquery_table.orders]
}

resource "google_bigquery_table" "orders_per_minute" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.mart.dataset_id
  table_id            = "orders_per_minute"
  deletion_protection = false
  view {
    use_legacy_sql = false
    query          = "SELECT * FROM `${var.project_id}.curated.orders_per_minute_mv`"
  }
  depends_on = [google_bigquery_table.orders_per_minute_mv]
}

# the mart views are AUTHORIZED to read curated: analysts never get access to curated itself
resource "google_bigquery_dataset_access" "authorize_masked" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated.dataset_id
  view {
    project_id = var.project_id
    dataset_id = google_bigquery_dataset.mart.dataset_id
    table_id   = google_bigquery_table.orders_masked.table_id
  }
}

resource "google_bigquery_dataset_access" "authorize_per_minute" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated.dataset_id
  view {
    project_id = var.project_id
    dataset_id = google_bigquery_dataset.mart.dataset_id
    table_id   = google_bigquery_table.orders_per_minute.table_id
  }
}

resource "google_bigquery_dataset_iam_member" "analyst_mart" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.mart.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.sa["sdp-analyst"].email}"
}

resource "google_project_iam_member" "analyst_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.sa["sdp-analyst"].email}"
}

resource "google_bigquery_dataset_iam_member" "enricher_curated" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.curated.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.sa["sdp-enricher"].email}"
}
