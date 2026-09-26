# 02 · Send events

**Bulk, through the real producer (Cloud Run job):**
```bash
gcloud run jobs execute generator --region $REGION --wait \
  --update-env-vars COUNT=300,POISON=6,DUPES=10,RUN_ID=demo1
```
`COUNT` valid events, `POISON` schema-valid but business-invalid (negative amount), `DUPES` re-sends of existing `event_id`s. `order_id` is `run-<RUN_ID>-<n>` so a run can be queried in isolation.

**By hand:**
```bash
gcloud pubsub topics publish events --message='{"event_id":"e-1","order_id":"o-1","customer_email":"a@b.co","amount":12.5,"currency":"EUR","event_time":1790462321569005}'
```
`event_time` is microseconds since epoch (Avro `timestamp-micros`).

**Schema rejection** *(Captured)*: publishing `{"hello":"world"}` returns
`INVALID_ARGUMENT: Invalid data in message: Message failed schema validation … Field was not found in JSON object: event_id.` and nothing is enqueued.
