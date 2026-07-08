#!/usr/bin/env python3
"""
forget_source.py
================
GDPR / right-to-be-forgotten helper for source_registry.

Hard-deletes one source AND its full source_reliability_event audit trail
in a single SurrealDB transaction. Used when legal requires removing all
record of a particular URL from the research pipeline.

Usage:
  python3 scripts/forget_source.py <url>          # delete by exact URL
  python3 scripts/forget_source.py --dry-run <url> # show what would be deleted
  python3 scripts/forget_source.py --id <urlhash>  # delete by registry id

The url-hash transformation matches the monolith convention:
  url.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 100)
"""

import argparse
import os
import re
import sys
import urllib.request
import urllib.error
import json
import base64

SURREAL_URL = os.environ.get("SURREAL_URL", "http://localhost:8001/sql")
SURREAL_NS = os.environ.get("SURREAL_NS", "research")
SURREAL_DB = os.environ.get("SURREAL_DB", "workflow")
SURREAL_USER = os.environ.get("SURREAL_USER", "root")
SURREAL_PASS = os.environ.get("SURREAL_PASS", "openclaw2026")


def url_to_hash(url: str) -> str:
    return re.sub(r"[^a-zA-Z0-9]", "_", url)[:100]


def sql(query: str) -> list:
    auth = base64.b64encode(f"{SURREAL_USER}:{SURREAL_PASS}".encode()).decode()
    req = urllib.request.Request(
        SURREAL_URL,
        data=query.encode(),
        headers={
            "Authorization": f"Basic {auth}",
            "surreal-ns": SURREAL_NS,
            "surreal-db": SURREAL_DB,
            "Content-Type": "text/plain",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"SurrealDB HTTP {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(2)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("url", nargs="?", help="exact URL to forget")
    g.add_argument("--id", dest="record_id", help="source_registry record id (hash form)")
    p.add_argument("--dry-run", action="store_true", help="show what would be deleted, do nothing")
    args = p.parse_args()

    record_id = args.record_id or url_to_hash(args.url)
    full_id = f"source_registry:`{record_id}`"

    # Inspect first
    inspect = sql(
        f"SELECT id, url, reputation_score, run_count FROM {full_id};\n"
        f"SELECT count() FROM source_reliability_event WHERE source = {full_id} GROUP ALL;"
    )

    src_rows = inspect[0].get("result") or []
    evt_count_rows = inspect[1].get("result") or []
    evt_count = (evt_count_rows[0].get("count") if evt_count_rows else 0) or 0

    if not src_rows:
        print(f"No source_registry row found for id={record_id}", file=sys.stderr)
        return 1

    src = src_rows[0]
    print(f"Target source : {src.get('id')}")
    print(f"  url         : {src.get('url')}")
    print(f"  reputation  : {src.get('reputation_score')}")
    print(f"  run_count   : {src.get('run_count')}")
    print(f"  audit events: {evt_count}")

    if args.dry_run:
        print("\n--dry-run: nothing deleted")
        return 0

    # Hard delete in one transaction
    delete_sql = (
        "BEGIN TRANSACTION;\n"
        f"DELETE source_reliability_event WHERE source = {full_id};\n"
        f"DELETE {full_id};\n"
        "COMMIT TRANSACTION;\n"
    )
    result = sql(delete_sql)
    statuses = [r.get("status") for r in result]
    if all(s == "OK" for s in statuses):
        print(f"\nDeleted source + {evt_count} audit events. statuses={statuses}")
        return 0
    else:
        print(f"\nDelete failed: {result}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
