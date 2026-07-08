#!/usr/bin/env python3
"""
migrate_add_user_support.py
===========================
Einmalige Migration: Multi-User-Support fuer das Research-System.

Aenderungen:
  1. Neue Tabelle research_user (nico, sabine)
  2. Neue Tabellen user_source_override, user_creator_preference
  3. Neue Felder: research_run.user_id, research_report.rating_user_id
  4. trigger_source ASSERT erweitert um 'hive' + 'openclaw_for_user'
  5. Bestehende Runs → user_id='nico', bestehende Ratings → rating_user_id='nico'

Usage:
  python3 scripts/migrate_add_user_support.py              # ausfuehren
  python3 scripts/migrate_add_user_support.py --dry-run     # nur SQL anzeigen
  python3 scripts/migrate_add_user_support.py --verify-only # nur Validierung
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

SURREAL_URL = os.environ.get("SURREAL_URL", "http://localhost:8001/sql")
SURREAL_NS = os.environ.get("SURREAL_NS", "research")
SURREAL_DB = os.environ.get("SURREAL_DB", "workflow")
SURREAL_USER = os.environ.get("SURREAL_USER", "root")
SURREAL_PASS = os.environ.get("SURREAL_PASS", "openclaw2026")

# User-Konfiguration — hier anpassen falls sich Chat-IDs oder Emails aendern
USERS = {
    "nico": {
        "email": "x18013@googlemail.com",
        "display_name": "Nico",
        "telegram_chat_id": 827301846,
    },
    "sabine": {
        "email": "sabinesauerdesign@gmail.com",
        "display_name": "Sabine",
        "telegram_chat_id": 6212851933,
    },
}


def sql(query: str) -> list:
    """Fuehrt SurrealQL gegen die Research-DB aus."""
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


# -- Schema-Definitionen (muessen idempotent sein — DEFINE ist upsert in SurrealDB 3.x) --

SCHEMA_SQL = """
-- research_user Tabelle
DEFINE TABLE research_user SCHEMAFULL;
DEFINE FIELD email            ON research_user TYPE string;
DEFINE FIELD display_name     ON research_user TYPE string;
DEFINE FIELD telegram_chat_id ON research_user TYPE option<int>;
DEFINE FIELD created_at       ON research_user TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_email ON research_user FIELDS email UNIQUE;

-- user_source_override Tabelle
DEFINE TABLE user_source_override SCHEMAFULL;
DEFINE FIELD user_id        ON user_source_override TYPE string;
DEFINE FIELD source         ON user_source_override TYPE record<source_registry>;
DEFINE FIELD trust_override ON user_source_override TYPE option<string>
  ASSERT $value IS NONE OR $value IN ["T1", "T2", "T3", "untrusted"];
DEFINE FIELD is_pinned      ON user_source_override TYPE bool DEFAULT false;
DEFINE FIELD is_blocked     ON user_source_override TYPE bool DEFAULT false;
DEFINE FIELD notes          ON user_source_override TYPE option<string>;
DEFINE FIELD updated_at     ON user_source_override TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_user_source ON user_source_override FIELDS user_id, source UNIQUE;
DEFINE INDEX idx_user        ON user_source_override FIELDS user_id;

-- user_creator_preference Tabelle
DEFINE TABLE user_creator_preference SCHEMAFULL;
DEFINE FIELD user_id    ON user_creator_preference TYPE string;
DEFINE FIELD creator    ON user_creator_preference TYPE record<creator>;
DEFINE FIELD following  ON user_creator_preference TYPE bool DEFAULT true;
DEFINE FIELD priority   ON user_creator_preference TYPE string DEFAULT "normal"
  ASSERT $value IN ["high", "normal", "muted"];
DEFINE FIELD updated_at ON user_creator_preference TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_user_creator ON user_creator_preference FIELDS user_id, creator UNIQUE;
DEFINE INDEX idx_user         ON user_creator_preference FIELDS user_id;

-- Neue Felder auf bestehenden Tabellen
DEFINE FIELD user_id ON research_run TYPE option<string>;
DEFINE INDEX idx_user ON research_run FIELDS user_id;
DEFINE FIELD rating_user_id ON research_report TYPE option<string>;

-- trigger_source ASSERT erweitern (absichtlicher Override — REMOVE+DEFINE noetig)
REMOVE FIELD trigger_source ON research_run;
DEFINE FIELD trigger_source ON research_run TYPE string
  ASSERT $value IN ["webhook", "schedule", "telegram", "manual", "portal", "openclaw", "hive", "openclaw_for_user"];
"""


def build_seed_sql() -> str:
    """Erzeugt CREATE-Statements fuer die User-Seed-Daten."""
    stmts = []
    for uid, data in USERS.items():
        chat_id = data["telegram_chat_id"]
        stmts.append(
            f'CREATE research_user:{uid} CONTENT {{'
            f' email: "{data["email"]}",'
            f' display_name: "{data["display_name"]}",'
            f" telegram_chat_id: {chat_id},"
            f" created_at: time::now()"
            f" }};"
        )
    return "\n".join(stmts)


BACKFILL_SQL = """
-- Bestehende Runs gehoeren Nico (einziger bisheriger User)
UPDATE research_run SET user_id = 'nico' WHERE user_id IS NONE;

-- Bestehende Ratings gehoeren Nico
UPDATE research_report SET rating_user_id = 'nico' WHERE user_rating IS NOT NONE AND rating_user_id IS NONE;
"""


VERIFY_SQL = """
SELECT count() AS total FROM research_user GROUP ALL;
SELECT count() AS total FROM research_run WHERE user_id IS NOT NONE GROUP ALL;
SELECT count() AS runs_without_user FROM research_run WHERE user_id IS NONE GROUP ALL;
SELECT count() AS rated_reports FROM research_report WHERE user_rating IS NOT NONE GROUP ALL;
SELECT count() AS rated_without_user FROM research_report WHERE user_rating IS NOT NONE AND rating_user_id IS NONE GROUP ALL;
"""


def run_migration(dry_run: bool = False) -> int:
    full_sql = SCHEMA_SQL + "\n" + build_seed_sql() + "\n" + BACKFILL_SQL

    if dry_run:
        print("=== DRY RUN — SQL das ausgefuehrt wuerde ===\n")
        print(full_sql)
        return 0

    print("Applying schema definitions...")
    results = sql(SCHEMA_SQL)
    # "already exists" ist tolerierbar bei Re-Runs (DEFINE ist idempotent fuer neue Objekte)
    fatal_errors = [
        r for r in results
        if r.get("status") != "OK" and "already exists" not in str(r.get("result", ""))
    ]
    warnings = [r for r in results if r.get("status") != "OK" and r not in fatal_errors]
    if warnings:
        print(f"  {len(warnings)} 'already exists' warnings (ignoriert)")
    if fatal_errors:
        print(f"Schema errors: {json.dumps(fatal_errors, indent=2)}", file=sys.stderr)
        return 1
    print(f"  {len(results) - len(warnings)} statements OK")

    print("Seeding research_user records...")
    seed_results = sql(build_seed_sql())
    for r in seed_results:
        if r.get("status") != "OK":
            # Koennte bereits existieren (UNIQUE constraint)
            print(f"  Seed warning: {r}", file=sys.stderr)
        else:
            rows = r.get("result", [])
            if rows:
                print(f"  Created: {rows[0].get('id', '?')}")

    print("Backfilling user_id on existing data...")
    backfill_results = sql(BACKFILL_SQL)
    for r in backfill_results:
        if r.get("status") == "OK":
            result = r.get("result", [])
            count = len(result) if isinstance(result, list) else 0
            print(f"  Updated {count} rows")
        else:
            print(f"  Backfill warning: {r}", file=sys.stderr)

    return verify()


def verify() -> int:
    print("\n=== Verification ===")
    results = sql(VERIFY_SQL)

    checks = [
        ("research_user count", 0, lambda r: r >= 2),
        ("research_run with user_id", 1, lambda r: True),
        ("research_run without user_id", 2, lambda r: r == 0),
        ("rated reports total", 3, lambda r: True),
        ("rated reports without rating_user_id", 4, lambda r: r == 0),
    ]

    all_ok = True
    for label, idx, check_fn in checks:
        rows = results[idx].get("result", [])
        value = rows[0].get("total", rows[0].get("runs_without_user", rows[0].get("rated_reports", rows[0].get("rated_without_user", 0)))) if rows else 0
        status = "OK" if check_fn(value) else "FAIL"
        if status == "FAIL":
            all_ok = False
        print(f"  {status}: {label} = {value}")

    if all_ok:
        print("\nMigration erfolgreich abgeschlossen.")
        return 0
    else:
        print("\nMigration hat Warnungen — bitte manuell pruefen.", file=sys.stderr)
        return 1


def main() -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--dry-run", action="store_true", help="SQL anzeigen, nichts ausfuehren")
    p.add_argument("--verify-only", action="store_true", help="Nur Validierung, keine Aenderungen")
    args = p.parse_args()

    if args.verify_only:
        return verify()

    return run_migration(dry_run=args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
