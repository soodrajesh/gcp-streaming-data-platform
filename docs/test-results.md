# Live test results

Captured by `scripts/test.sh` on 2026-09-26T22:37:52Z against project `claude-code-507112` (europe-west1).

```

── 1. Topology ──
  PASS  topic 'events' enforces the Avro schema (JSON encoding)  [projects/claude-code-507112/schemas/order-event	JSON ]
  PASS  events-to-bq is a BigQuery subscription (topic schema, metadata)  [claude-code-507112.raw.events	True ]
  PASS  events-to-enricher pushes with OIDC and dead-letters after 5 attempts  [sdp-push@claude-code-507112.iam.gserviceaccount.com	5 ]
  PASS  dead-letter topic drains to BigQuery  [claude-code-507112.raw.dead_letters ]

── 2. Bad data is stopped at the door (schema validation) ──
  PASS  a message that violates the schema is rejected at publish  [ERROR: (gcloud.pubsub.topics.publish) INVALID_ARGUMENT: Invalid data in message: Message f]
  PASS  wrong field type (amount as string) is rejected  [ERROR: (gcloud.pubsub.topics.publish) INVALID_ARGUMENT: Invalid data in message: Message f]

── 3. End to end: 300 valid + 6 poison + 10 duplicate events ──
  running Cloud Run job 'generator' (run id 1790462272)…
  PASS  generator job finished successfully (exit code)  [0 ]
  PASS  raw.events landed every published message (BigQuery subscription)  [316 ]
  PASS  raw keeps duplicates: 316 rows but 306 distinct event ids  [306 ]
  PASS  curated.orders has exactly the 300 valid events (poison excluded)  [300 ]
  waiting for the 6 poison events to exhaust 5 delivery attempts and reach the DLQ…
  PASS  the 6 poison events landed in raw.dead_letters  [6 ]
    delivery-count attribute on the dead letters: 5  (Pub/Sub counts attempts approximately; see runbook 08)
  PASS  dead-lettered only after the retry budget (delivery count >= 5)  [5 ]
  PASS  no invalid row reached curated  [0 ]

── 4. Exactly-once at read time, and the numbers add up ──
  PASS  mart.orders_masked has 300 rows: de-duplicated by event_id  [300 ]
  PASS  every enriched amount_eur equals amount × fx_rate  [0 ]
  PASS  materialized view orders_per_minute agrees with the base table  [match ]

── 5. Latency (publish → enriched row), this run ──
    p50 / p95 event→enriched (ms): 2207 5588   (includes Cloud Run cold start)
  PASS  p95 event→enriched under 60 s  [2207 5588 ]

── 6. Governance: an analyst sees marts, never PII ──
  PASS  analyst can query mart.orders_masked  [300 ]
    columns the analyst sees: event_id,order_id,customer_key,amount,currency,amount_eur,event_time
  PASS  masked view exposes customer_key, not customer_email  [event_id,order_id,customer_key,amount,currency,amount_eur,event_time ]
  PASS  …and no email column  [absent: email]
  PASS  analyst is denied curated.orders (PII)  [BigQuery error in query operation: Error processing job 'claude- code-507112:bqjob_r50b3f2]
  PASS  analyst is denied raw.events  [BigQuery error in query operation: Error processing job 'claude- code-507112:bqjob_r7a82a8]

── 7. Service security ──
  PASS  enricher rejects unauthenticated calls (403)  [403 ]
  PASS  only sdp-push may invoke it (no allUsers)  [['serviceAccount:sdp-push@claude-code-507112.iam.gserviceaccount.com'] ]
  PASS  …and allUsers is not bound  [absent: allUsers]
  PASS  no user-managed service-account keys exist  [0 ]

── 8. Operability ──
  PASS  backlog alert policy exists  [Streaming: events are not being consumed (oldest unacked > 5 min) Streaming: poison events]
  PASS  poison-event alert policy exists  [Streaming: events are not being consumed (oldest unacked > 5 min) Streaming: poison events]
  PASS  dashboard exists  [Streaming data platform ]
```

**Result: 29 passed, 0 failed.**
