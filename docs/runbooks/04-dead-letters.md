# 04 · Dead letters & replay

**When:** the alert *"poison events reached the dead-letter topic"* fires.

1. **What failed, and why?** *(Captured — [evidence](../evidence/dead-letters.txt))*
```bash
bq query --nouse_legacy_sql "SELECT JSON_VALUE(data,'\$.order_id') AS order_id, JSON_VALUE(data,'\$.amount') AS amount,
  JSON_VALUE(attributes,'\$.CloudPubSubDeadLetterSourceDeliveryCount') AS deliveries FROM \`$PROJECT.raw.dead_letters\` ORDER BY publish_time DESC LIMIT 20"
```
Then read the reason from the enricher's structured logs:
```bash
gcloud logging read 'resource.labels.service_name="enricher" AND jsonPayload.message="poison event"' --freshness 1h --limit 10 --format='value(jsonPayload.reason,jsonPayload.message_id)'
```
2. **Decide:** producer bug (fix upstream, then replay) or genuinely bad data (leave in the DLQ table as the audit record).
3. **Replay one message** *(Captured, live — [evidence](../evidence/replay.txt))*: fix the payload, republish to `events`; it flows through the normal path.
```bash
MSG=$(bq query --nouse_legacy_sql --format=json "SELECT data FROM \`$PROJECT.raw.dead_letters\` WHERE JSON_VALUE(data,'\$.order_id')='<ORDER_ID>' LIMIT 1" \
  | python3 -c "import sys,json; e=json.loads(json.load(sys.stdin)[0]['data']); e['amount']=abs(e['amount']); print(json.dumps(e))")
gcloud pubsub topics publish events --message="$MSG"
```
Same `event_id` ⇒ the mart de-duplicates if it was somehow already present.
4. **Prove it:** query `mart.orders_masked` for that `order_id`.

**If it goes wrong:** publish fails with `INVALID_ARGUMENT` ⇒ your fix broke the schema (`event_time` must be an integer of microseconds). Replayed message dead-letters again ⇒ the enricher still rejects it; check the logged `reason`.
