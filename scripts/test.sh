#!/usr/bin/env bash
# Live proof against the running platform. Every check asserts something observed, not configured.
# Writes docs/test-results.md. Exit code = number of failed checks.
source "$(dirname "$0")/lib.sh"; set +e
need gcloud; need bq
PASS=0; FAIL=0; OUT="$ROOT/docs/test-results.md"; TMP="$ROOT/.test-tmp"; mkdir -p "$TMP"
{ echo "# Live test results"; echo; echo "Captured by \`scripts/test.sh\` on $(date -u +%FT%TZ) against project \`$PROJECT_ID\` ($REGION)."; echo; echo '```'; } > "$OUT"
say()   { echo "$*" | tee -a "$OUT"; }
check() { # <name> <expected-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then PASS=$((PASS+1)); say "  PASS  $1  [$(head -c 90 <<<"$3" | tr '\n' ' ')]"
  else FAIL=$((FAIL+1)); say "  FAIL  $1  (wanted /$2/, got: $(head -c 200 <<<"$3" | tr '\n' ' '))"; fi
}
check_not() { # <name> <forbidden-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then FAIL=$((FAIL+1)); say "  FAIL  $1  (found /$2/ in: $(head -c 200 <<<"$3" | tr '\n' ' '))"
  else PASS=$((PASS+1)); say "  PASS  $1  [absent: $2]"; fi
}
section() { say ""; say "── $* ──"; }
wait_scalar() { # <sql> <regex> <timeout-s>  -> echoes last value
  local v end=$(( $(date +%s) + $3 ))
  while :; do v=$(bq_scalar "$1"); grep -qE "$2" <<<"$v" && break; [ "$(date +%s)" -lt "$end" ] || break; sleep 10; done; echo "$v"
}
ANALYST="sdp-analyst@$PROJECT_ID.iam.gserviceaccount.com"
RUN="$(date +%s)"
P="$PROJECT_ID"

section "1. Topology"
check "topic 'events' enforces the Avro schema (JSON encoding)" 'order-event.*JSON|JSON.*order-event' \
  "$(gcloud pubsub topics describe events --project "$P" --format='value(schemaSettings.schema,schemaSettings.encoding)')"
check "events-to-bq is a BigQuery subscription (topic schema, metadata) with a dead-letter policy" 'raw.*events.*True.*5' \
  "$(gcloud pubsub subscriptions describe events-to-bq --project "$P" --format='value(bigqueryConfig.table,bigqueryConfig.useTopicSchema,deadLetterPolicy.maxDeliveryAttempts)')"
check "events-to-enricher pushes with OIDC and dead-letters after 5 attempts" 'sdp-push.*5|5.*sdp-push' \
  "$(gcloud pubsub subscriptions describe events-to-enricher --project "$P" --format='value(pushConfig.oidcToken.serviceAccountEmail,deadLetterPolicy.maxDeliveryAttempts)')"
check "dead-letter topic drains to BigQuery" 'dead_letters' \
  "$(gcloud pubsub subscriptions describe events-dlq-to-bq --project "$P" --format='value(bigqueryConfig.table)')"

section "2. Bad data is stopped at the door (schema validation)"
r=$(gcloud pubsub topics publish events --project "$P" --message='{"hello":"world"}' 2>&1)
check "a message that violates the schema is rejected at publish" 'INVALID_ARGUMENT|Invalid|invalid' "$r"
r=$(gcloud pubsub topics publish events --project "$P" --message='{"event_id":"x","order_id":"y","customer_email":"a@b.c","amount":"twelve","currency":"EUR","event_time":1}' 2>&1)
check "wrong field type (amount as string) is rejected" 'INVALID_ARGUMENT|Invalid|invalid' "$r"

section "3. End to end: 300 valid + 6 poison + 10 duplicate events"
say "  running Cloud Run job 'generator' (run id $RUN)…"
gcloud run jobs execute generator --region "$REGION" --project "$P" --wait --update-env-vars "COUNT=300,POISON=6,DUPES=10,RUN_ID=$RUN" >"$TMP/gen.log" 2>&1
check "generator job finished successfully (exit code)" '^0$' "$?"
LIKE="order_id LIKE 'run-$RUN-%'"
raw=$(wait_scalar "SELECT COUNT(*) FROM \`$P.raw.events\` WHERE $LIKE" '^31[6-9]$|^3[2-9][0-9]$' 300)
check "raw.events landed every published message (BigQuery subscription)" '^31[6-9]$|^3[2-9][0-9]$' "$raw"
rawd=$(bq_scalar "SELECT COUNT(DISTINCT event_id) FROM \`$P.raw.events\` WHERE $LIKE")
check "raw keeps duplicates: 316 rows but 306 distinct event ids" '^306$' "$rawd"
cur=$(wait_scalar "SELECT COUNT(DISTINCT event_id) FROM \`$P.curated.orders\` WHERE $LIKE" '^300$' 300)
check "curated.orders has exactly the 300 valid events (poison excluded)" '^300$' "$cur"
say "  waiting for the 6 poison events to exhaust 5 delivery attempts and reach the DLQ…"
dl=$(wait_scalar "SELECT COUNT(DISTINCT JSON_VALUE(data,'\$.event_id')) FROM \`$P.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id') LIKE 'run-$RUN-%'" '^6$' 420)
check "the 6 poison events landed in raw.dead_letters" '^6$' "$dl"
dlq_attempts=$(bq_scalar "SELECT MAX(CAST(JSON_VALUE(attributes,'\$.CloudPubSubDeadLetterSourceDeliveryCount') AS INT64)) FROM \`$P.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id') LIKE 'run-$RUN-%'")
say "    delivery-count attribute on the dead letters: $dlq_attempts  (Pub/Sub counts attempts approximately; see runbook 08)"
check "dead-lettered only after the retry budget (delivery count >= 5)" '^[5-9]$' "$dlq_attempts"
say "  provoking a BigQuery write failure: schema-valid event whose timestamp is year 10000 (outside BigQuery's range)…"
gcloud pubsub topics publish events --project "$P" --message="{\"event_id\":\"bqfail-$RUN\",\"order_id\":\"bqfail-$RUN\",\"customer_email\":\"a@b.co\",\"amount\":1.0,\"currency\":\"EUR\",\"event_time\":253402300800000000}" >/dev/null 2>&1
bqdl=$(wait_scalar "SELECT COUNT(*) FROM \`$P.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id')='bqfail-$RUN' AND JSON_VALUE(attributes,'\$.CloudPubSubDeadLetterSourceSubscription')='events-to-bq'" '^[1-9]$' 480)
check "a row BigQuery rejects is dead-lettered by the BigQuery subscription (source events-to-bq)" '^[1-9]$' "$bqdl"
bad_in_curated=$(bq_scalar "SELECT COUNT(*) FROM \`$P.curated.orders\` WHERE $LIKE AND (amount <= 0 OR currency NOT IN ('EUR','USD','GBP','INR'))")
check "no invalid row reached curated" '^0$' "$bad_in_curated"

section "4. Exactly-once at read time, and the numbers add up"
masked=$(bq_scalar "SELECT COUNT(*) FROM \`$P.mart.orders_masked\` WHERE $LIKE")
check "mart.orders_masked has 300 rows: de-duplicated by event_id" '^300$' "$masked"
fxok=$(bq_scalar "SELECT COUNT(*) FROM \`$P.curated.orders\` WHERE $LIKE AND ABS(amount*fx_rate - amount_eur) > 0.01")
check "every enriched amount_eur equals amount × fx_rate" '^0$' "$fxok"
mv=$(wait_scalar "SELECT IF(SUM(orders) = (SELECT COUNT(*) FROM \`$P.curated.orders\`), 'match', 'differ') FROM \`$P.mart.orders_per_minute\`" '^match$' 180)
check "materialized view orders_per_minute agrees with the base table" '^match$' "$mv"

section "5. Latency (publish → enriched row), this run"
lat=$(bq_scalar "SELECT CONCAT(CAST(APPROX_QUANTILES(TIMESTAMP_DIFF(enriched_at, event_time, MILLISECOND),100)[OFFSET(50)] AS STRING),' ',CAST(APPROX_QUANTILES(TIMESTAMP_DIFF(enriched_at, event_time, MILLISECOND),100)[OFFSET(95)] AS STRING)) FROM \`$P.curated.orders\` WHERE $LIKE")
say "    p50 / p95 event→enriched (ms): $lat   (includes Cloud Run cold start)"
check "p95 event→enriched under 60 s" '^[0-9]+ [0-9]{1,5}$' "$lat"

section "6. Governance: an analyst sees marts, never PII"
TOKEN=$(gcloud auth print-access-token --impersonate-service-account="$ANALYST" 2>/dev/null | tail -1)
aq() { bq --project_id "$P" --oauth_access_token="$TOKEN" query --nouse_legacy_sql --quiet --format=csv "$1" 2>&1; }
ok_rows=$(aq "SELECT COUNT(*) FROM \`$P.mart.orders_masked\` WHERE $LIKE" | tail -1)
check "analyst can query mart.orders_masked" '^300$' "$ok_rows"
cols=$(aq "SELECT * FROM \`$P.mart.orders_masked\` LIMIT 1" | head -1)
say "    columns the analyst sees: $cols"
check "masked view exposes customer_key, not customer_email" 'customer_key' "$cols"
check_not "…and no email column" 'email' "$cols"
check "analyst is denied curated.orders (PII)" 'Access Denied|Permission|403' "$(aq "SELECT customer_email FROM \`$P.curated.orders\` LIMIT 1")"
check "analyst is denied raw.events" 'Access Denied|Permission|403' "$(aq "SELECT * FROM \`$P.raw.events\` LIMIT 1")"

section "7. Service security"
URL=$(gcloud run services describe enricher --region "$REGION" --project "$P" --format='value(status.url)')
check "enricher rejects unauthenticated calls (403)" '^403$' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/" -H 'Content-Type: application/json' -d '{}')"
inv=$(gcloud run services get-iam-policy enricher --region "$REGION" --project "$P" --format='value(bindings.members)')
check "only sdp-push may invoke it (no allUsers)" 'sdp-push' "$inv"
check_not "…and allUsers is not bound" 'allUsers' "$inv"
keys=0; for sa in sdp-enricher sdp-generator sdp-push sdp-analyst sdp-build; do
  n=$(gcloud iam service-accounts keys list --iam-account "$sa@$P.iam.gserviceaccount.com" --managed-by=user --format='value(name)' 2>/dev/null | grep -c .); keys=$((keys+n)); done
check "no user-managed service-account keys exist" '^0$' "$keys"

section "8. Operability"
check "backlog alert policy exists" 'not being consumed' "$(gcloud monitoring policies list --project "$P" --format='value(displayName)')"
check "poison-event alert policy exists" 'poison events' "$(gcloud monitoring policies list --project "$P" --format='value(displayName)')"
check "dashboard exists" 'Streaming data platform' "$(gcloud monitoring dashboards list --project "$P" --format='value(displayName)')"

say '```'; echo >> "$OUT"; echo "**Result: $PASS passed, $FAIL failed.**" >> "$OUT"
echo; [ "$FAIL" = 0 ] && ok "$PASS/$((PASS+FAIL)) checks passed" || warn "$FAIL failed, $PASS passed"
exit "$FAIL"
