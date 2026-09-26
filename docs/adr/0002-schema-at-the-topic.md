# ADR 0002 — Enforce the Avro schema on the topic

**Status:** accepted

A message that does not match `order_event.avsc` is rejected **at publish time** with `INVALID_ARGUMENT` (proved live: a `{"hello":"world"}` message and a message with `amount` as a string are both refused). Malformed data never enters a subscription, so nothing downstream has to defend against it, and producers get the error immediately.

**What the schema cannot catch:** business rules. A negative amount is a valid `double`. Those are handled by the enricher and the dead-letter path (ADR 0003), which is why the generator deliberately produces schema-valid poison events.

**Evolution:** add fields as optional (union with `null` + default) and commit a new schema revision; never rename or retype in place. See [runbook 06](../runbooks/06-schema-evolution.md).
