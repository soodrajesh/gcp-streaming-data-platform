# One service account per job to be done; none is broader than it needs to be.
locals {
  sas = {
    "sdp-enricher"  = "Cloud Run enricher: validates events, writes curated.orders"
    "sdp-generator" = "Cloud Run job: publishes synthetic events (publisher only)"
    "sdp-push"      = "Identity Pub/Sub presents (OIDC) when pushing to the enricher"
    "sdp-analyst"   = "Demo analyst: may read only the masked marts"
    "sdp-build"     = "Cloud Build: builds and pushes the image"
  }
  pubsub_agent = "serviceAccount:${google_project_service_identity.pubsub.email}"
}

resource "google_service_account" "sa" {
  for_each     = local.sas
  project      = var.project_id
  account_id   = each.key
  display_name = each.value
  depends_on   = [google_project_service.apis]
}

# ── build ─────────────────────────────────────────────────────────────────────────────────────────
resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "sdp"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_storage_bucket" "build" {
  project                     = var.project_id
  name                        = "${var.project_id}-sdp-build"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.sa["sdp-build"].email}"
}

resource "google_artifact_registry_repository_iam_member" "build_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.sa["sdp-build"].email}"
}

resource "google_storage_bucket_iam_member" "build_src" {
  bucket = google_storage_bucket.build.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.sa["sdp-build"].email}"
}

resource "google_project_iam_member" "operator" {
  for_each = toset(["roles/iam.serviceAccountUser", "roles/run.developer"])
  project  = var.project_id
  role     = each.value
  member   = "user:${var.admin_email}"
}

# operator may impersonate the analyst to prove what an analyst can and cannot read
resource "google_service_account_iam_member" "impersonate_analyst" {
  service_account_id = google_service_account.sa["sdp-analyst"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.admin_email}"
}
