# ADR 0001 — BigQuery subscription for the raw landing zone (no Dataflow, no code)

**Status:** accepted

Every accepted message must be stored untouched for audit and replay. Options: a Dataflow template, a Cloud Run consumer, or a **Pub/Sub BigQuery subscription**. The subscription is a managed feature: it writes each message to a table using the *topic's schema*, adds publish metadata (`message_id`, `publish_time`, `attributes`), scales with the topic and costs nothing beyond Pub/Sub throughput. No worker to size, patch or monitor.

**Trade-offs.** It is at-least-once, so `raw.events` can contain duplicates (the tests prove this: 316 rows, 306 distinct). It cannot transform or reject — hence the *second* path (push → enricher) for validation/enrichment. Messages that BigQuery cannot accept are retried and then dead-lettered by Pub/Sub (`max_delivery_attempts = 5`, same DLQ as the enricher; proven live by publishing a schema-valid event with a year-10000 timestamp, see [test §3](../test-results.md)); the subscription's IAM (dataEditor + metadataViewer on `raw` only) keeps its blast radius to one dataset.
