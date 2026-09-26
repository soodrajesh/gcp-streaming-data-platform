# ADR 0004 — Authorized views, not table grants, for analyst access

**Status:** accepted

`curated.orders` holds the customer email. Analysts get `dataViewer` on the `mart` dataset only; the views in `mart` are **authorized** on `curated`, so they can read it on the analyst's behalf. The masked view exposes `customer_key = first 12 hex chars of SHA-256(lower(email))` (stable for joins, not reversible by inspection), and de-duplicates by `event_id` so consumers get exactly-once results from an at-least-once pipeline.

Proved live by impersonating the analyst service account: `mart.orders_masked` → 300 rows with no email column; `curated.orders` and `raw.events` → *Access Denied*.

**Trade-offs:** an unsalted hash of a low-entropy value can be brute-forced — use a keyed hash (`KEYS.*` / Cloud KMS) or column-level policy tags if the threat model includes a motivated analyst. Authorized views need updating when the view set changes (Terraform owns it).
