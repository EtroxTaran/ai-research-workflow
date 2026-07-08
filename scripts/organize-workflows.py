#!/usr/bin/env python3
"""
organize-workflows.py
=====================
Organizes n8n workflows into folders and assigns clean tags.

Approach: Direct SQLite manipulation (n8n v2.14.2, community edition).
Run BEFORE restarting n8n to avoid cache conflicts, then restart n8n.

Usage:
  python3 scripts/organize-workflows.py [--dry-run]
"""

import sqlite3
import json
import sys
import secrets
import string
from datetime import datetime, timezone

DB_PATH = "/home/clawd/.n8n/database.sqlite"
DRY_RUN = "--dry-run" in sys.argv
PROJECT_ID = "8NMDFJItxjOGmGGk"  # Personal project of Nico

# Folder definitions
FOLDERS = [
    {"name": "Hive", "key": "hive"},
    {"name": "Research", "key": "research"},
    {"name": "KB", "key": "kb"},
]

# Tag definitions (final clean set)
TAGS = ["hive", "research", "kb"]

# Tags to remove (stale/unused)
STALE_TAGS = ["kb-ingest", "research-workflow", "research-pipeline", "phase-1", "deliver"]

# Workflow -> folder + tag assignments
WORKFLOW_GROUPS = {
    "hive": [
        "0jSgDJmQ2jVevrN5",  # Hive - Architecture Evaluator
        "s52ae4UHrVUiMTlK",  # Hive - Auto-Review Trigger
        "EKTLqWKi3w9RvDxF",  # Hive - Correction Router
        "RWppN4c34UK70MMQ",  # Hive - Cost Reporter
        "cjXs4VxtgiF9QJaP",  # Hive - Creative Divergence
        "gMm8bKjFy722Q0kb",  # Hive - Gate Evaluator
        "rfqdv7Q4nEhnemPY",  # Hive - Health Monitor
        "Vv0jlkYJCMnfkN83",  # Hive - Notification Router
        "8ncQpfVxJCj1sM3A",  # Hive - Pipeline Advancer
        "b23HHqMeMu4ZP1jz",  # Hive - Product Research
        "vUo73JHgtThGbXAv",  # Hive - Rate Limit Failover
        "emlKf2JJbtS3wLFo",  # Hive - Retrospective Analyzer
        "dX5wsM4NLkSEHv05",  # Hive - Scout Failover Watchdog
        "jOboCnk65YqILzW4",  # Hive - Security Scanner
        "siTpZ5GJ1eIY0WAN",  # Hive - Specialist Coverage
        "qTtokH57tUDc24Ag",  # Hive - Tech Stack Resolver
    ],
    "research": [
        "yRsHld8Yfi7I4WzA",  # Research Continuous Monitor
        "TMg2GpvBwSIEQIqA",  # Research Creator Discovery
        "63h9DuPDCwuxAZZD",  # Research Feedback Handler
        "69QGdrWQneaaph5Z",  # Research Pipeline MVP
        "72CMlkiGvzcLQ5Yv",  # Research Weekly Digest
    ],
    "kb": [
        "kb-rss-ingest-1",      # KB RSS Ingest (Miniflux)
        "kb-webhook-ingest-1",  # KB Webhook URL Submit
    ],
}

# Workflows whose IDs are resolved at runtime by name lookup (self-healing
# across re-imports). Useful for newer workflows whose IDs were allocated by
# `n8n import:workflow` rather than hardcoded.
NEW_WORKFLOWS_BY_NAME = {
    "research": ["Research HITL Response (Agent Callback)"],
    "hive":     ["Hive - Research Callback"],
}


def nanoid(size=16):
    """Generate a nanoid-style random ID (alphanumeric)."""
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(size))


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


def run(conn, sql, params=()):
    cur = conn.cursor()
    if DRY_RUN:
        print(f"  [DRY-RUN] {sql[:120]} | params={params}")
        return cur
    cur.execute(sql, params)
    return cur


def main():
    print(f"{'[DRY-RUN] ' if DRY_RUN else ''}Organizing n8n workflows...")
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # 0. Resolve dynamically-imported workflows by name
    print("\n[0] Resolving workflows by name (self-healing across re-imports)...")
    for group, names in NEW_WORKFLOWS_BY_NAME.items():
        for name in names:
            row = cur.execute(
                "SELECT id FROM workflow_entity WHERE name=?", (name,)
            ).fetchone()
            if row:
                if row["id"] not in WORKFLOW_GROUPS[group]:
                    WORKFLOW_GROUPS[group].append(row["id"])
                    print(f"  Resolved '{name}' -> {row['id']} ({group})")
                else:
                    print(f"  '{name}' already in group '{group}' ({row['id']})")
            else:
                print(f"  WARNING: '{name}' not found in DB — import it first")

    # 1. Clean up orphaned tag assignments (workflows that no longer exist)
    print("\n[1] Cleaning orphaned tag assignments...")
    existing_ids = {r[0] for r in cur.execute("SELECT id FROM workflow_entity").fetchall()}
    orphans = cur.execute(
        "SELECT workflowId, tagId FROM workflows_tags"
    ).fetchall()
    for o in orphans:
        if o["workflowId"] not in existing_ids:
            print(f"  Removing orphaned tag assignment: workflowId={o['workflowId']}")
            run(conn, "DELETE FROM workflows_tags WHERE workflowId=? AND tagId=?",
                (o["workflowId"], o["tagId"]))

    # 2. Remove stale tags (and their remaining assignments)
    print("\n[2] Removing stale tags...")
    for tag_name in STALE_TAGS:
        row = cur.execute("SELECT id FROM tag_entity WHERE name=?", (tag_name,)).fetchone()
        if row:
            tag_id = row["id"]
            run(conn, "DELETE FROM workflows_tags WHERE tagId=?", (tag_id,))
            run(conn, "DELETE FROM tag_entity WHERE id=?", (tag_id,))
            print(f"  Deleted tag '{tag_name}' (id={tag_id})")
        else:
            print(f"  Tag '{tag_name}' not found — skipping")

    # 3. Create new tags
    print("\n[3] Creating clean tags...")
    tag_ids = {}
    for tag_name in TAGS:
        existing = cur.execute("SELECT id FROM tag_entity WHERE name=?", (tag_name,)).fetchone()
        if existing:
            tag_ids[tag_name] = existing["id"]
            print(f"  Tag '{tag_name}' already exists (id={existing['id']})")
        else:
            tid = nanoid(16)
            run(conn, "INSERT INTO tag_entity (id, name, createdAt, updatedAt) VALUES (?,?,?,?)",
                (tid, tag_name, now_iso(), now_iso()))
            tag_ids[tag_name] = tid
            print(f"  Created tag '{tag_name}' (id={tid})")
    if not DRY_RUN:
        conn.commit()
        # Re-fetch tag IDs after commit
        for tag_name in TAGS:
            row = cur.execute("SELECT id FROM tag_entity WHERE name=?", (tag_name,)).fetchone()
            if row:
                tag_ids[tag_name] = row["id"]

    # 4. Create folders
    print("\n[4] Creating folders...")
    folder_ids = {}
    for f in FOLDERS:
        existing = cur.execute(
            "SELECT id FROM folder WHERE name=? AND projectId=?", (f["name"], PROJECT_ID)
        ).fetchone()
        if existing:
            folder_ids[f["key"]] = existing["id"]
            print(f"  Folder '{f['name']}' already exists (id={existing['id']})")
        else:
            fid = nanoid(16)
            run(conn, "INSERT INTO folder (id, name, parentFolderId, projectId, createdAt, updatedAt) VALUES (?,?,NULL,?,?,?)",
                (fid, f["name"], PROJECT_ID, now_iso(), now_iso()))
            folder_ids[f["key"]] = fid
            print(f"  Created folder '{f['name']}' (id={fid})")
    if not DRY_RUN:
        conn.commit()
        for f in FOLDERS:
            row = cur.execute(
                "SELECT id FROM folder WHERE name=? AND projectId=?", (f["name"], PROJECT_ID)
            ).fetchone()
            if row:
                folder_ids[f["key"]] = row["id"]

    # 5. Assign workflows to folders + tags
    print("\n[5] Assigning workflows to folders and tags...")
    for group, wf_ids in WORKFLOW_GROUPS.items():
        folder_id = folder_ids.get(group)
        tag_id = tag_ids.get(group)
        for wf_id in wf_ids:
            row = cur.execute("SELECT name FROM workflow_entity WHERE id=?", (wf_id,)).fetchone()
            if not row:
                print(f"  WARNING: workflow {wf_id} not found in DB — skipping")
                continue
            wf_name = row["name"]
            # Assign folder
            run(conn, "UPDATE workflow_entity SET parentFolderId=?, updatedAt=? WHERE id=?",
                (folder_id, now_iso(), wf_id))
            # Remove existing tag assignments for this workflow
            run(conn, "DELETE FROM workflows_tags WHERE workflowId=?", (wf_id,))
            # Assign new tag
            if tag_id:
                run(conn, "INSERT OR IGNORE INTO workflows_tags (workflowId, tagId) VALUES (?,?)",
                    (wf_id, tag_id))
            print(f"  [{group}] {wf_name} -> folder={folder_id}, tag={tag_id}")

    if not DRY_RUN:
        conn.commit()
        print("\nAll changes committed to SQLite.")
        print("IMPORTANT: Restart n8n to refresh its cache:")
        print("  systemctl --user restart n8n")
    else:
        print("\n[DRY-RUN] No changes written. Run without --dry-run to apply.")

    conn.close()

    # Summary
    print("\n=== Summary ===")
    print(f"Folders created: {', '.join(f['name'] for f in FOLDERS)}")
    print(f"Tags created: {', '.join(TAGS)}")
    print(f"Tags removed: {', '.join(STALE_TAGS)}")
    print(f"Workflows organized: {sum(len(v) for v in WORKFLOW_GROUPS.values())}")


if __name__ == "__main__":
    main()
