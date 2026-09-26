# 06 · Schema evolution

Adding a field, safely:
1. Add it to `app/order_event.avsc` as **optional**: `{"name": "coupon", "type": ["null", "string"], "default": null}`.
2. Add the column to `raw.events` (nullable) in `terraform/bigquery.tf` **before** the schema revision goes live, otherwise the BigQuery subscription cannot map the field.
3. `terraform apply` (creates a new Pub/Sub schema revision), deploy producers, then update the enricher/`curated.orders`/views.

Never rename or retype a field in place: old producers would start failing at publish. If you must, create `order-event-v2` + a new topic and migrate.
