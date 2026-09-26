from datetime import datetime, timezone

import pytest

from app.enricher import Poison, app, enrich, validate

GOOD = {
    "event_id": "e1",
    "order_id": "o1",
    "customer_email": " Ana@Example.com ",
    "amount": 100.0,
    "currency": "USD",
    "event_time": 1_758_000_000_000_000,
}


def test_valid_event_passes_and_is_enriched():
    validate(GOOD)
    row = enrich(GOOD, now=datetime(2026, 1, 1, tzinfo=timezone.utc))
    assert row["customer_email"] == "ana@example.com"
    assert row["amount_eur"] == 92.0 and row["fx_rate"] == 0.92
    assert row["event_time"].startswith("2025-09-16")


@pytest.mark.parametrize("patch", [{"amount": -5}, {"amount": 0}, {"currency": "XXX"}, {"customer_email": "nope"}])
def test_poison_events_are_rejected(patch):
    with pytest.raises(Poison):
        validate({**GOOD, **patch})


def test_missing_field_is_poison():
    bad = dict(GOOD)
    del bad["order_id"]
    with pytest.raises(Poison):
        validate(bad)


def test_health():
    assert app.test_client().get("/").get_json() == {"status": "ok"}


def test_push_rejects_non_envelope():
    assert app.test_client().post("/", json={"x": 1}).status_code == 400


def test_push_poison_returns_422_so_pubsub_retries_then_dead_letters():
    import base64
    import json

    data = base64.b64encode(json.dumps({**GOOD, "amount": -1}).encode()).decode()
    r = app.test_client().post("/", json={"message": {"data": data, "messageId": "m1"}})
    assert r.status_code == 422
