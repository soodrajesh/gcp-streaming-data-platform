# 08 · Troubleshooting — problems actually hit while building this

| # | Symptom | Cause | Fix |
|---|---|---|---|
| S1 | `bq: Unknown command line flag 'impersonate_service_account'` | `bq` has no such flag (gcloud does) | `gcloud auth print-access-token --impersonate-service-account=…` then `bq --oauth_access_token=…` |
| S2 | Test expected exactly 5 delivery attempts, got 6 in one run and 5 in the next | Pub/Sub counts attempts approximately; handler logs showed 3–5 invocations per message | Assert "≥ 5 delivery count", and document approximate semantics ([ADR 0003](../adr/0003-dead-letter-and-replay.md)) |
| S3 | `gcloud run jobs execute --wait` check failed on output text | Output format is not a stable contract | Check the exit code instead |
| S4 | Replaying a dead letter failed with *Tried to parse invalid JSON* | `bq --format=csv` wraps and escapes JSON | Use `--format=json` and parse with `json.loads` |
| S5 | Negative-match test with `(?!…)` never matched | `grep -E` has no lookahead | Add a `check_not` helper |
| S6 | Terraform: BigQuery subscription needs the Pub/Sub service agent to exist | Agent is created lazily | `google_project_service_identity` (google-beta) creates it first, and IAM depends on its email |
| S7 | Cloud Run + push subscription need an image that does not exist yet | chicken-and-egg | Two-phase apply: `count = var.image == "" ? 0 : 1` on the dependent resources |
