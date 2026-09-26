"""Pub/Sub push endpoint: validate an order event, enrich it, write it to curated.orders.

Delivery contract (this is what makes the dead-letter path work):
  2xx  -> acknowledged
  422  -> permanent failure (poison); Pub/Sub retries with backoff and, after 5 attempts, dead-letters it
  500  -> transient failure (BigQuery error); same retry policy, but a healthy retry succeeds
"""

import base64
import json
import logging
import os
from datetime import datetime, timezone

from flask import Flask, request

app = Flask(__name__)
log = logging.getLogger("enricher")
logging.basicConfig(level=logging.INFO, format="%(message)s")

FX_TO_EUR = {"EUR": 1.0, "USD": 0.92, "GBP": 1.17, "INR": 0.011}
REQUIRED = ("event_id", "order_id", "customer_email", "amount", "currency", "event_time")
_client = None


class Poison(ValueError):
    """The event can never be processed; retrying is pointless (but harmless)."""


def validate(e: dict) -> None:
    missing = [k for k in REQUIRED if k not in e]
    if missing:
        raise Poison(f"missing fields: {missing}")
    if not isinstance(e["amount"], (int, float)) or e["amount"] <= 0:
        raise Poison(f"amount must be > 0, got {e['amount']!r}")
    if e["currency"] not in FX_TO_EUR:
        raise Poison(f"unsupported currency {e['currency']!r}")
    if "@" not in e["customer_email"]:
        raise Poison("customer_email is not an email address")


def enrich(e: dict, now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    rate = FX_TO_EUR[e["currency"]]
    return {
        "event_id": e["event_id"],
        "order_id": e["order_id"],
        "customer_email": e["customer_email"].strip().lower(),
        "amount": float(e["amount"]),
        "currency": e["currency"],
        "event_time": datetime.fromtimestamp(e["event_time"] / 1_000_000, tz=timezone.utc).isoformat(),
        "amount_eur": round(e["amount"] * rate, 4),
        "fx_rate": rate,
        "enriched_at": now.isoformat(),
    }


def bq():
    global _client
    if _client is None:
        from google.cloud import bigquery

        _client = bigquery.Client()
    return _client


@app.get("/")
def health():
    return {"status": "ok"}


@app.post("/")
def push():
    envelope = request.get_json(silent=True) or {}
    msg = envelope.get("message")
    if not msg or "data" not in msg:
        return {"error": "not a Pub/Sub push envelope"}, 400
    try:
        event = json.loads(base64.b64decode(msg["data"]))
        validate(event)
        row = enrich(event)
    except (Poison, ValueError, KeyError, TypeError) as exc:
        log.warning(
            json.dumps({"severity": "WARNING", "message": "poison event", "reason": str(exc), "message_id": msg.get("messageId")})
        )
        return {"error": str(exc)}, 422

    errors = bq().insert_rows_json(os.environ["TARGET_TABLE"], [row], row_ids=[row["event_id"]])
    if errors:
        log.error(json.dumps({"severity": "ERROR", "message": "bigquery insert failed", "errors": errors}))
        return {"error": "insert failed"}, 500
    return "", 204
