#!/usr/bin/env bash
# Re-captures docs/evidence/*.txt from the LIVE platform (run after up.sh + test.sh).
# Render: python3 docs/diagrams/termshot.py "<title>" docs/evidence/<f>.txt docs/img/<f>.png
source "$(dirname "$0")/lib.sh"; set +e
E="$ROOT/docs/evidence"; mkdir -p "$E"; P="$PROJECT_ID"
run() { echo "\$ $1"; eval "$1" 2>&1; echo; }
bqq() { bq --project_id "$P" query --nouse_legacy_sql --quiet --format=pretty "$1" 2>&1; }
LAST="$(bq_scalar "SELECT MAX(REGEXP_EXTRACT(order_id, r'run-(\d+)-')) FROM \`$P.raw.events\`")"

{ echo "\$ # last run: $LAST  (300 valid + 6 poison + 10 duplicates published)"; echo
  echo "\$ bq query  # where did each of the 316 published messages end up?"
  bqq "SELECT 'raw.events (rows)' AS stage, COUNT(*) AS n FROM \`$P.raw.events\` WHERE order_id LIKE 'run-$LAST-%'
       UNION ALL SELECT 'raw.events (distinct event_id)', COUNT(DISTINCT event_id) FROM \`$P.raw.events\` WHERE order_id LIKE 'run-$LAST-%'
       UNION ALL SELECT 'curated.orders (distinct)', COUNT(DISTINCT event_id) FROM \`$P.curated.orders\` WHERE order_id LIKE 'run-$LAST-%'
       UNION ALL SELECT 'mart.orders_masked (de-duplicated)', COUNT(*) FROM \`$P.mart.orders_masked\` WHERE order_id LIKE 'run-$LAST-%'
       UNION ALL SELECT 'raw.dead_letters (poison)', COUNT(DISTINCT JSON_VALUE(data,'\$.event_id')) FROM \`$P.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id') LIKE 'run-$LAST-%'"; echo
} > "$E/pipeline-counts.txt"

{ echo "\$ bq query  # dead letters: the poison events, with their reason for inspection"
  bqq "SELECT JSON_VALUE(data,'\$.order_id') AS order_id, JSON_VALUE(data,'\$.amount') AS amount, JSON_VALUE(data,'\$.currency') AS cur,
       JSON_VALUE(attributes,'\$.CloudPubSubDeadLetterSourceDeliveryCount') AS deliveries,
       JSON_VALUE(attributes,'\$.CloudPubSubDeadLetterSourceSubscription') AS source_sub
       FROM \`$P.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id') LIKE 'run-$LAST-%' ORDER BY 1"; echo
} > "$E/dead-letters.txt"

TOKEN=$(gcloud auth print-access-token --impersonate-service-account="sdp-analyst@$P.iam.gserviceaccount.com" 2>/dev/null | tail -1)
aq() { bq --project_id "$P" --oauth_access_token="$TOKEN" query --nouse_legacy_sql --quiet --format=pretty "$1" 2>&1 | head -${2:-12}; }
{ echo "\$ # as sdp-analyst (impersonated): masked mart"
  echo "\$ bq query 'SELECT * FROM mart.orders_masked LIMIT 3'"; aq "SELECT * FROM \`$P.mart.orders_masked\` LIMIT 3"; echo
  echo "\$ bq query 'SELECT customer_email FROM curated.orders LIMIT 1'"; aq "SELECT customer_email FROM \`$P.curated.orders\` LIMIT 1" 3; echo
  echo "\$ bq query 'SELECT * FROM raw.events LIMIT 1'"; aq "SELECT * FROM \`$P.raw.events\` LIMIT 1" 3; echo
} > "$E/analyst-access.txt"

{ run "gcloud pubsub subscriptions list --project $P --format='table(name.basename():label=SUBSCRIPTION,topic.basename():label=TOPIC,bigqueryConfig.table.basename():label=BQ_TABLE,pushConfig.pushEndpoint.basename():label=PUSH,deadLetterPolicy.maxDeliveryAttempts:label=DLQ_AFTER)'"
  run "gcloud pubsub topics describe events --project $P --format='yaml(name,schemaSettings)'"
  run "gcloud pubsub topics publish events --project $P --message='{\"hello\":\"world\"}' 2>&1 | cut -c1-150"
  run "gcloud run services list --project $P --format='table(metadata.name:label=SERVICE,status.url:label=URL)'"
} > "$E/pubsub-topology.txt"
ok "evidence written to docs/evidence/"
