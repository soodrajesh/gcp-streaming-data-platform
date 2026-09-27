#!/usr/bin/env python3
"""Generates docs/img/architecture.svg (PNG via docs/diagrams/render.py).

    python3 docs/diagrams/architecture.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from archlib import Diagram  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "img", "architecture.svg")

W, H = 1780, 1500
d = Diagram(W, H, "Streaming Data Platform on Google Cloud",
            "Pub/Sub (Avro schema) · BigQuery subscription · Cloud Run enricher · dead-lettering · authorized views · Terraform")

d.group(190, 100, 1400, 690, "Google Cloud project  ·  europe-west1  ·  BigQuery location EU", "#1a73e8", dash=False, fill="#f8faff", label_w=560)

d.node("gen", 320, 250, "Generator", "run", "compute", "Cloud Run job\nCOUNT · POISON · DUPES")
d.node("topic", 570, 250, "Pub/Sub topic\nevents", "bolt", "data", "Avro schema · JSON\nbad data rejected at publish")
d.node("raw", 1000, 250, "raw.events", "db", "data", "append-only landing\npartitioned by publish_time")
d.node("mv", 1300, 250, "", "chart", "data")
d.text(1262, 246, "orders_per_minute", 12.5, "#202124", "600", "end")
d.text(1262, 262, "materialized view · refresh 60 s", 10.5, "#5f6368", "400", "end")

d.node("enr", 1000, 450, "", "run", "compute")
d.text(1000, 378, "Enricher", 12.5, "#202124", "600", "middle")
d.text(1000, 392, "Cloud Run · OIDC push", 10.5, "#5f6368", "400", "middle")
d.text(1000, 405, "validate · FX · insert", 10.5, "#5f6368", "400", "middle")
d.node("cur", 1300, 450, "curated.orders", "db", "data", "PII · keyed insert\nevent_id = row id")

d.node("dlq", 1000, 660, "events-dlq", "bolt", "data", "dead-letter topic\nafter 5 attempts")
d.node("dead", 1300, 660, "raw.dead_letters", "db", "data", "payload + attributes\nfor inspection / replay")

d.node("marts", 1510, 350, "mart views", "filter", "security", "authorized · de-dup\nemail → customer_key")
d.node("analyst", 1700, 350, "Analyst", "user", "actor", "sdp-analyst\nmarts only")

# 1 publish
d.edge("gen", "topic", "h", num=1, label="publish JSON")
# 2 BigQuery subscription (topic -> raw)
d.edge("topic", "raw", "h", num=2, label="BigQuery subscription (no code)")
# 3 push subscription
d.path([(760, 250), (760, 450), (972, 450)], num=3, label="push subscription + OIDC", lab_at=(860, 450))
# 4 write curated
d.edge("enr", "cur", "h", num=4, label="insert_rows_json")
d.edge("cur", "mv", "v", half_a=28, half_b=28)
# 5 poison -> dlq
d.edge("enr", "dlq", "v", num=5, color="#d93025", label="422 → retries → 5th failure", lab_dy=0)
# 6 dlq -> bq
d.edge("dlq", "dead", "h", num=6, color="#d93025", label="BigQuery subscription")
# 7 analyst
d.path([(1328, 250), (1440, 250), (1440, 320), (1482, 320)], num=None)
d.path([(1328, 450), (1440, 450), (1440, 380), (1482, 380)], num=None)
d.edge("marts", "analyst", "h", num=7, half_a=28, half_b=28)

d.text(1010, 150, "Every hop is at-least-once: raw keeps duplicates on purpose; the mart de-duplicates at read time.", 12, "#5f6368", "600")

# ── ops / governance ─────────────────────────────────────────────────────────────────────────────
d.band(190, 830, 1400, 190, "OBSERVABILITY  ·  the pipeline reports on itself", "#1e8e3e", "#f6fcf8")
d.node("o1", 330, 930, "Dashboard", "chart", "ops", "publish rate · backlog\nDLQ · p95 latency")
d.node("o2", 620, 930, "Backlog alert", "bolt", "ops", "oldest unacked > 5 min")
d.node("o3", 910, 930, "Poison alert", "bolt", "ops", "any message on events-dlq")
d.node("o4", 1200, 930, "Cloud Logging", "policy", "ops", "structured poison logs\nwith message_id + reason")
d.node("o5", 1470, 930, "Budget", "money", "ops", "€ alerts 50 / 100 %")

d.band(190, 1040, 1400, 130, "GOVERNANCE  ·  preventive controls", "#d93025", "#fff8f7")
d.text(220, 1084, "One service account per job: generator = publisher only · push identity = only invoker of the enricher (no allUsers) · enricher = write curated only", 12.5, "#3c4043")
d.text(220, 1108, "No service-account keys anywhere · analysts hold no access to raw/curated, only to authorized views that hash the email · schema violations never enter the system", 12.5, "#3c4043")
d.text(220, 1132, "Build: dedicated Cloud Build SA, digest-pinned image · state in a versioned private bucket", 12.5, "#3c4043")

d.legend(34, 1210, "Numbered flows", [
    ("1", "The generator (Cloud Run job) publishes JSON order events; the topic validates each against the Avro schema and rejects anything else"),
    ("2", "A BigQuery subscription writes every accepted message straight into raw.events with publish metadata: no code to run or scale"),
    ("3", "A push subscription calls the enricher with an OIDC token; a 2xx acknowledges the message"),
    ("4", "The enricher validates, converts to EUR, and inserts into curated.orders (event_id as the insert id); a materialized view aggregates per minute"),
    ("5", "Invalid events return 422; Pub/Sub retries with backoff and after 5 attempts forwards the message to events-dlq"),
    ("6", "A second BigQuery subscription lands dead letters in raw.dead_letters (rows BigQuery itself rejects are forwarded to the same DLQ), and the poison alert fires"),
    ("7", "Analysts query mart views only; the views are authorized on curated, so no direct table access is ever granted"),
], w=1710)
d.key(34, 1430)

if __name__ == "__main__":
    d.save(OUT)
    print("wrote", os.path.abspath(OUT))
