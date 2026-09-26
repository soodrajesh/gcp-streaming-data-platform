# Runbooks

Each runbook: **When** · **Commands** · **Output** · **If it goes wrong**.

> **Output status.** Blocks headed *Captured* are real output from the live deployment (2026-09-26). Nothing here is invented.

```bash
export PROJECT=$(gcloud config get-value project) REGION=europe-west1
```

| # | Runbook | Use it when |
|---|---|---|
| 01 | [Build & teardown](01-build-and-teardown.md) | Standing the platform up / down |
| 02 | [Send events](02-send-events.md) | Producing test traffic; publishing by hand |
| 03 | [Query the data](03-query-the-data.md) | Analysis, reconciliation, latency |
| 04 | [Dead letters & replay](04-dead-letters.md) | The poison alert fires |
| 05 | [Incident response](05-incident-response.md) | Backlog alert, errors, nothing arriving |
| 06 | [Schema evolution](06-schema-evolution.md) | Adding a field to the event |
| 07 | [Cost](07-cost.md) | Bill questions |
| 08 | [Troubleshooting](08-troubleshooting.md) | Problems already hit during development |
