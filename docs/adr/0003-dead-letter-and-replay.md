# ADR 0003 — Retry, dead-letter, and replay instead of drop or block

**Status:** accepted

The push endpoint returns **422** for events that can never succeed and **500** for transient failures. Pub/Sub retries with a 5–20 s backoff; after `max_delivery_attempts = 5` it forwards the message to `events-dlq`, which a second BigQuery subscription lands in `raw.dead_letters` (payload + attributes including the source subscription and delivery count). A poison event therefore neither blocks the queue nor disappears: it is queryable, alerts fire, and after a fix it can be republished ([runbook 04](../runbooks/04-dead-letters.md), verified live).

**Trade-off:** Pub/Sub's attempt counting is approximate. In this build the enricher logged 3–5 invocations per poison message and the forwarded attribute read 5 in one run and 6 in another. The design assumes "about five", never exactly five.
