# Streaming Data Platform on Google Cloud

An event pipeline you can trust: **Pub/Sub with an enforced Avro schema** → a **BigQuery subscription** for a raw, replayable landing zone → a **Cloud Run enricher** with retries and **dead-lettering** → **curated** tables → **PII-masked authorized views** for analysts. Provisioned and destroyed by **one script each**, and every claim is asserted against the running system.

> **Status: deployed and verified live** (europe-west1 / BigQuery EU, 2026-09-26). `./scripts/up.sh` builds it in two Terraform phases and [`scripts/test.sh`](scripts/test.sh) passes **30 of 30** ([results](docs/test-results.md)). The dead-letter replay in [runbook 04](docs/runbooks/04-dead-letters.md) was executed for real. The stack was then removed with `./scripts/down.sh`.

```bash
gcloud config set project <your-project>      # billing linked; the rest is auto-detected
./scripts/up.sh       # infra → image build → Cloud Run + subscriptions → live tests
./scripts/down.sh     # delete everything (--purge also drops the state)
```

## What it proves

| Concern | Mechanism | Proven by |
|---|---|---|
| **Bad data stopped at the door** | Avro schema on the topic; wrong shape/type → `INVALID_ARGUMENT` at publish | test §2 |
| **Nothing lost** | BigQuery subscription lands every accepted message untouched | test §3: 316 rows for 316 published |
| **Poison doesn't block or vanish** | 422 → retries → dead-letter topic → `raw.dead_letters` + alert; replayable. BigQuery write failures dead-letter too | test §3 (both sources), runbook 04 |
| **Exactly-once results from at-least-once delivery** | duplicates kept in raw, removed at read by `event_id` | 316 → 306 → 300 |
| **PII never reaches analysts** | authorized views, hashed `customer_key`; no table grants | test §6 (impersonated analyst) |
| **Least privilege** | one SA per job; only the push identity can invoke the enricher; no SA keys | test §7 |
| **Operable** | backlog and poison alerts, dashboard, structured logs, budget | test §8 |
| **Fast enough** | event → enriched row p50 2.2 s / p95 5.6 s warm | test §5 |

## Architecture

[![Architecture](docs/img/architecture.png)](docs/img/architecture.svg)

<sub>Click for the vector version. Diagram source: [`docs/diagrams/architecture.py`](docs/diagrams/architecture.py).</sub>

More: [architecture & delivery semantics](docs/architecture.md) · [threat model](docs/threat-model.md)

## Design decisions

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-bigquery-subscription-for-landing.md) | BigQuery subscription for raw landing (no Dataflow, no code) |
| [0002](docs/adr/0002-schema-at-the-topic.md) | Enforce the Avro schema at the topic |
| [0003](docs/adr/0003-dead-letter-and-replay.md) | Retry → dead-letter → replay (attempt counts are approximate) |
| [0004](docs/adr/0004-authorized-views-for-analysts.md) | Authorized views, not table grants |

## Runbooks

[docs/runbooks](docs/runbooks/README.md): build & teardown · send events · query the data · dead letters & replay · incident response · schema evolution · cost · troubleshooting.

## Repository layout

```
terraform/   pubsub · bigquery · run · identities · monitoring (two-phase: image-dependent resources use count)
app/         enricher (Flask push endpoint) · generator (Cloud Run job) · Avro schema · unit tests
scripts/     up.sh · down.sh · test.sh · capture-evidence.sh
docs/        architecture · ADRs · runbooks · threat model · evidence · diagrams
```

## Cost & safety

Well under €1 for a full build-test-teardown; Cloud Run scales to zero; a budget with alerts is created by Terraform; `down.sh` deletes datasets with their contents.

## Known gaps (deliberate)

No CMEK / VPC Service Controls / column policy tags (org-level) · unsalted hash for `customer_key` (use a keyed hash for real PII) · single region · streaming inserts are best-effort deduplicated (the mart is the source of truth) · synthetic producer.

## License

MIT
