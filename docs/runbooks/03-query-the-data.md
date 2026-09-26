# 03 · Query the data

**Reconcile a run** *(Captured, see [evidence](../evidence/pipeline-counts.txt))*:
```bash
bq query --nouse_legacy_sql "
SELECT 'raw.events (rows)', COUNT(*) FROM \`$PROJECT.raw.events\` WHERE order_id LIKE 'run-<RUN_ID>-%'
UNION ALL SELECT 'curated.orders (distinct)', COUNT(DISTINCT event_id) FROM \`$PROJECT.curated.orders\` WHERE order_id LIKE 'run-<RUN_ID>-%'
UNION ALL SELECT 'raw.dead_letters', COUNT(DISTINCT JSON_VALUE(data,'\$.event_id')) FROM \`$PROJECT.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id') LIKE 'run-<RUN_ID>-%'"
```
316 published → 316 raw rows (306 distinct) → 300 curated → 300 in the mart → 6 dead letters.

**Latency (event → enriched)** *(Captured p50/p95: 2.2 s / 5.6 s warm)*:
```sql
SELECT APPROX_QUANTILES(TIMESTAMP_DIFF(enriched_at, event_time, MILLISECOND), 100)[OFFSET(50)] AS p50_ms,
       APPROX_QUANTILES(TIMESTAMP_DIFF(enriched_at, event_time, MILLISECOND), 100)[OFFSET(95)] AS p95_ms
FROM `<project>.curated.orders` WHERE order_id LIKE 'run-<RUN_ID>-%'
```
**As the analyst** (impersonation needs `serviceAccountTokenCreator`, granted to the operator by Terraform):
```bash
TOKEN=$(gcloud auth print-access-token --impersonate-service-account=sdp-analyst@$PROJECT.iam.gserviceaccount.com)
bq --oauth_access_token="$TOKEN" query --nouse_legacy_sql 'SELECT * FROM `'$PROJECT'.mart.orders_masked` LIMIT 3'
```
(`bq` has no `--impersonate_service_account` flag; use a token.)
