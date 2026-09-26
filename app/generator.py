"""Publishes synthetic order events. Env: TOPIC, COUNT, POISON, DUPES, RUN_ID."""

import json
import os
import random
import sys
import time
import uuid

from google.cloud import pubsub_v1

EMAILS = ["ana@example.com", "Bo@Example.com", "chen@example.org", "dee@example.net", "eli@example.com"]
CURRENCIES = ["EUR", "USD", "GBP", "INR"]


def make_event(run: str, i: int, poison: bool = False) -> dict:
    return {
        "event_id": str(uuid.uuid4()),
        "order_id": f"run-{run}-{i:05d}",
        "customer_email": random.choice(EMAILS),
        "amount": (-1.0 * round(random.uniform(1, 50), 2)) if poison else round(random.uniform(5, 500), 2),
        "currency": random.choice(CURRENCIES),
        "event_time": int(time.time() * 1_000_000),
    }


def main() -> int:
    topic = os.environ["TOPIC"]
    count = int(os.environ.get("COUNT", "100"))
    poison = int(os.environ.get("POISON", "0"))
    dupes = int(os.environ.get("DUPES", "0"))
    run = os.environ.get("RUN_ID", str(int(time.time())))

    events = [make_event(run, i) for i in range(count)]
    events += [make_event(run, count + i, poison=True) for i in range(poison)]
    events += [dict(e) for e in random.sample(events[:count], min(dupes, count))]  # same event_id again

    pub = pubsub_v1.PublisherClient()
    futures = [pub.publish(topic, json.dumps(e).encode()) for e in events]
    for f in futures:
        f.result(timeout=60)
    print(
        json.dumps({"run_id": run, "published": len(events), "valid": count, "poison": poison, "duplicates": min(dupes, count)})
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
