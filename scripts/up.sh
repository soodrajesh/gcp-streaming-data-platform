#!/usr/bin/env bash
# Build the whole streaming platform end to end, then prove it works:
#   state bucket -> topics/schema/BigQuery/IAM/monitoring -> image build -> Cloud Run + subscriptions -> live tests.
# Two Terraform phases because the Cloud Run service and its push subscription need the image digest.
# Idempotent. `--plan` shows the phase-1 plan and stops. `--skip-tests` skips the final test suite.
source "$(dirname "$0")/lib.sh"
PLAN_ONLY=0; SKIP_TESTS=0
for a in "$@"; do case "$a" in --plan) PLAN_ONLY=1;; --skip-tests) SKIP_TESTS=1;; esac; done
need gcloud; need terraform; need bq

log "Project $PROJECT_ID · $REGION · billing $BILLING_ACCOUNT_ID · admin $ADMIN_EMAIL"
log "1/5 Terraform state bucket"
"$ROOT/scripts/bootstrap.sh" "$PROJECT_ID" "$REGION" >/dev/null && ok "gs://$STATE_BUCKET"
tf_init
[ "$PLAN_ONLY" = 1 ] && { $TF plan -input=false; exit 0; }

log "2/5 Phase 1: topics, Avro schema, BigQuery, IAM, monitoring, registry"
# Re-runs must not tear down phase-2 resources: keep the previous image during phase 1.
[ -s "$ROOT/.last-image" ] && export TF_VAR_image="$(cat "$ROOT/.last-image")"
$TF apply -input=false -auto-approve
out() { $TF output -raw "$1"; }
REPO="$(out artifact_repo)"; BUCKET="$(out build_bucket)"; BUILD_SA="$(out build_sa)"

log "3/5 Build the image (Cloud Build, dedicated least-privilege SA)"
TAG="v$(date +%y%m%d-%H%M%S)"
gcloud builds submit --project "$PROJECT_ID" --region "$REGION" --config cloudbuild.yaml \
  --service-account "projects/$PROJECT_ID/serviceAccounts/$BUILD_SA" \
  --gcs-source-staging-dir "gs://$BUCKET/src" --substitutions "_REPO=$REPO,_TAG=$TAG" .
DIGEST="$(gcloud artifacts docker images describe "$REPO/pipeline:$TAG" --format='get(image_summary.digest)')"
IMG="$REPO/pipeline@$DIGEST"; ok "image $IMG"; echo "$IMG" > "$ROOT/.last-image"

log "4/5 Phase 2: Cloud Run enricher + generator job + push subscription with dead-lettering"
export TF_VAR_image="$IMG"
$TF apply -input=false -auto-approve
ok "applied"

if [ "$SKIP_TESTS" = 1 ]; then log "Skipping tests"; else log "5/5 Live test suite"; "$ROOT/scripts/test.sh"; fi
log "DONE — tear down with ./scripts/down.sh"
