# ⚠️ ARCHIVED — Consolidated into ai-portal

As of 2026-04-15, this repository has been merged into `~/projects/ai-portal` as
the single source of truth for the research pipeline.

## Where to find what

| Asset | New location |
|-------|--------------|
| n8n workflows (25 JSONs) | `ai-portal/n8n/workflows/` |
| Runtime n8n instance | `ai-portal/docker-compose.yml` (service `n8n`, host network, port 5678) |
| Credentials & execution history | migrated via raw filesystem copy of `~/.n8n/` into Docker volume `ai-portal_n8n_data` |
| SurrealDB schema (research domain) | `ai-portal/plugins/research-plugin/src/infrastructure/schema.surql` |
| Ops scripts | `ai-portal/scripts/research-forget-source.py`, `research-prune-reliability-events.sh`, `research-migrate-user-support.py` |
| Operational notes (SurrealDB 3.x gotchas, n8n patterns, smoke-test ladder) | `ai-portal/CLAUDE.md` § "Research Pipeline — Operational Notes" |

## Why this repo is kept (not deleted)

Full git history of the pipeline development (Sprint 1 + Sprint 2, ~6 months)
remains valuable for archaeology and blame. Do not force-push or delete.

## Runtime state at time of archive

- SurrealDB: migrated from native `:8001` → Docker `ai-portal-surrealdb` at `:18000`.
  Native `:8001` may still be running as a 7-day fallback; stop manually after
  2026-04-22 if no issues surface.
- n8n: native `systemctl --user n8n` disabled; Docker `ai-portal-n8n` runs on
  host network, port 5678, with the migrated SQLite (25 workflows, 1 credential,
  1945 executions).
- Crontab: `/home/clawd/projects/ai-portal/scripts/research-prune-reliability-events.sh`.

Migration plan: `~/.claude/plans/luminous-seeking-puppy.md`.
