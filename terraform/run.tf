resource "google_cloud_run_v2_service" "enricher" {
  count               = var.image == "" ? 0 : 1
  project             = var.project_id
  name                = "enricher"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.sa["sdp-enricher"].email
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
    containers {
      image   = var.image
      command = ["gunicorn"]
      args    = ["--bind=:8080", "--workers=1", "--threads=8", "--timeout=30", "app.enricher:app"]
      env {
        name  = "TARGET_TABLE"
        value = "${var.project_id}.curated.orders"
      }
      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }
    }
  }
  depends_on = [google_bigquery_dataset_iam_member.enricher_curated]
}

# only the push identity may invoke the enricher (no allUsers)
resource "google_cloud_run_v2_service_iam_member" "push_invoker" {
  count    = var.image == "" ? 0 : 1
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.enricher[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.sa["sdp-push"].email}"
}

resource "google_project_iam_member" "enricher_bq_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.sa["sdp-enricher"].email}"
}

resource "google_cloud_run_v2_job" "generator" {
  count               = var.image == "" ? 0 : 1
  project             = var.project_id
  name                = "generator"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.sa["sdp-generator"].email
      max_retries     = 0
      containers {
        image   = var.image
        command = ["python"]
        args    = ["-m", "app.generator"]
        env {
          name  = "TOPIC"
          value = google_pubsub_topic.events.id
        }
        resources {
          limits = { cpu = "1", memory = "512Mi" }
        }
      }
    }
  }
}
