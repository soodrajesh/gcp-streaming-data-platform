# 01 · Build & teardown

```bash
gcloud config set project <project>
./scripts/up.sh            # ≈ 3 min infra + build + ≈ 6 min tests
./scripts/up.sh --plan
./scripts/up.sh --skip-tests
./scripts/down.sh          # --purge also removes this repo's state
```
`up.sh` runs Terraform in **two phases** because the Cloud Run service and its push subscription need the image digest: phase 1 (topics, Avro schema, datasets, IAM, alerts, registry) → Cloud Build (dedicated SA) → phase 2 (Cloud Run service + job, push subscription with dead-lettering) → `scripts/test.sh`.

`down.sh` destroys everything (57 phase-1 + 5 phase-2 resources), including dataset contents, then prints what is left (Cloud Run services/jobs, topics, subscriptions, datasets — all should be `0`).
