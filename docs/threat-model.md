# Threat model (STRIDE, data-pipeline scope)

| Threat | Control | Proven by |
|---|---|---|
| **S**poofed publisher | Only `sdp-generator` has `pubsub.publisher`; no SA keys exist | test §7 (0 keys) |
| **S**poofed push caller | Enricher requires IAM auth; only `sdp-push` is invoker; no `allUsers` | test §7 (403 unauthenticated) |
| **T**ampered / malformed data | Avro schema at the topic; business validation in the enricher; poison never reaches `curated` | test §2, §3 |
| **R**epudiation / lost events | Raw landing keeps everything incl. duplicates; DLQ keeps failures with attributes | test §3 (316 → 306 → 300 + 6) |
| **I**nformation disclosure (PII) | Email only in `curated`; analysts read only hashed authorized views | test §6 |
| **D**enial of service (poison loop, backlog) | 5-attempt cap then DLQ; backlog + poison alerts; Cloud Run max 5 instances; budget | test §8 |
| **E**levation via the pipeline identity | Each SA is scoped to one dataset/topic; enricher cannot read raw | Terraform IAM |

**Out of scope:** CMEK, VPC Service Controls, per-column policy tags (need org/taxonomy), cross-region DR, a real schema registry workflow.
