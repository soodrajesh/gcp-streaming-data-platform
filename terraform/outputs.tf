output "artifact_repo" { value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}" }
output "build_bucket" { value = google_storage_bucket.build.name }
output "build_sa" { value = google_service_account.sa["sdp-build"].email }
output "analyst_sa" { value = google_service_account.sa["sdp-analyst"].email }
output "topic" { value = google_pubsub_topic.events.id }
