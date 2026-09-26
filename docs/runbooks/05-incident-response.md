# 05 · Incident response

| Alert / symptom | First look | Likely cause / action |
|---|---|---|
| **Oldest unacked > 5 min** | Dashboard *Oldest unacked age*; `gcloud pubsub subscriptions describe events-to-enricher` | Enricher failing or scaled to a limit → `gcloud run services logs read enricher --region $REGION --limit 50`; raise `max_instance_count`; check BigQuery errors |
| **Poison events on the DLQ** | [runbook 04](04-dead-letters.md) | Producer bug or bad data |
| Nothing arrives in `raw.events` | `gcloud pubsub topics list-subscriptions events`; subscription state | BigQuery subscription paused because the Pub/Sub service agent lost `dataEditor` on `raw`, or the table schema drifted from the topic schema |
| Rows in `raw`, none in `curated` | enricher logs | 403 from Cloud Run (push identity/audience wrong), or `sdp-enricher` lost `dataEditor` on `curated` |
| Publishers get `INVALID_ARGUMENT` | schema revision vs. payload | Producer deployed ahead of schema change → [runbook 06](06-schema-evolution.md) |

**Rollback:** `gcloud run services update-traffic enricher --region $REGION --to-revisions=<previous>=100`. Messages retry for up to the subscription's retention, so a bad enricher release delays data, it does not lose it.
