# 07 · Cost

| Item | While running |
|---|---|
| Pub/Sub (first 10 GB/month free) | ≈ €0 at demo volume |
| BigQuery storage/queries (KBs of data; slot-free) | cents |
| Streaming inserts | ≈ €0.01 per 200 MB |
| Cloud Run `min_instance_count = 0` | €0 when idle; pennies per burst |
| Materialized view refresh, Cloud Build, Artifact Registry | cents |

The whole build-test-teardown cycle costs well under €1. A Terraform-managed budget (€10 default) emails at 50 % and 100 %. After `down.sh` the cost is €0.
