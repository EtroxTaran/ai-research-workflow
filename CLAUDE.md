## CLAUDE.md — research-workflow-n8n

Project-specific rules. The global `~/.claude/CLAUDE.md` (always-latest, plan-first, no-assumptions, no-de-scoping) still applies.

---

## What this repo is

n8n monolith workflow + SurrealDB schema + ops scripts for the research pipeline. The single source of truth for "what runs in production" is:
- Workflow JSON: `workflows/research-orchestrator-monolith.json` (workflow id `69QGdrWQneaaph5Z`)
- DB schema: `schema/research-workflow.surql`
- Ops scripts: `scripts/*.{py,sh}`

n8n itself runs as `systemctl --user n8n` from `~/.config/systemd/user/n8n.service` against SurrealDB at `127.0.0.1:8001` (ns=`research`, db=`workflow`, root creds in env).

Memory files for this repo live at `~/.claude/projects/-home-clawd-projects-research-workflow-n8n/memory/` — read them at session start; they hold the slowly-changing context (infrastructure decisions, sprint outcomes).

---

## Hard rules for this repo

1. **Production code is the workflow JSON.** Per global Rule 2, do not push monolith changes without Nico's explicit OK in this conversation. Local edits + smoke tests are fine; commit + push are not, until asked.
2. **Schema additions are append-only.** Never edit an existing `DEFINE FIELD` / `DEFINE TABLE` in `schema/research-workflow.surql` without a deliberate migration plan — SurrealDB does not have automatic schema rewrites.
3. **Never re-introduce the `?versioned=true` idea.** It was rejected after Context7 verification:
   - SurrealKV is officially beta
   - The `VERSION` clause is alpha and only supports CREATE+SELECT (no UPDATE/DELETE)
   - `source_registry` has UNIQUE INDEX on `url` so "one row per change" is impossible
   - Hard-delete becomes effectively impossible (GDPR concern)
   The replacement is the `source_reliability_event` audit table — keep using it.
4. **Plan-first, then verify with Context7 + web before committing to any non-trivial mechanism.** This is how the `?versioned=true` mistake was caught.

---

## SurrealDB 3.x gotchas (learned the hard way)

These will bite anyone touching `source_registry`, the audit table, or any new SurrealQL in this repo.

### A. Multi-SET evaluates RHS using OLD field values

```sql
-- WRONG: reputation_score is computed against the PRE-increment correct_count
UPDATE source_registry:hash SET
  correct_count += 1,
  reputation_score = (correct_count + 1) / (correct_count + incorrect_count + 2);
```

The increment and the formula run "in parallel" — the formula sees the row state from before the SET. Always split:

```sql
-- RIGHT: two statements, formula uses post-increment values
UPDATE source_registry:hash SET correct_count += 1;
UPDATE source_registry:hash SET reputation_score = (correct_count + 1.0) / (correct_count + incorrect_count + 2.0);
```

### B. Integer division silently truncates

`(int + 1) / (int + int + 2)` returns an int. `1/2 = 0`. Always use float literals (`1.0`, `2.0`) when the result must be a float field. The original `D: Reputation Update` node had this bug for ~6 months — it never visibly corrupted production only because the per-row first-feedback path had not been hit yet.

### C. Use `BEGIN/COMMIT TRANSACTION` for any multi-statement write

Audit-trail desync is the worst kind of bug. The reputation update path now wraps everything (per-source LET → UPDATE → UPDATE → LET → CREATE, plus bulk auto-promote/downgrade) in one transaction. Do not break this pattern.

### D. FOR loop over a LET-captured array works fine inside a transaction

```sql
LET $candidates = (SELECT id FROM source_registry WHERE reputation_score >= 0.85 AND trust_level != 'high');
UPDATE $candidates SET trust_level = 'high';
FOR $c IN $candidates {
  CREATE source_reliability_event CONTENT { source: $c.id, event_type: 'manual_override', ... };
};
```

This is the bulk-event pattern in `D: Reputation Update`. Don't replace it with N round-trips.

---

## Source-reliability audit trail

Time-series of every reputation-affecting event lives in `source_reliability_event`. The user-facing "find drifting sources" query is:

```sql
SELECT source, math::sum(delta) AS net_change
FROM source_reliability_event
WHERE created_at > time::now() - 14d
GROUP BY source
HAVING net_change < -0.2
ORDER BY net_change ASC;
```

Retention: weekly cron (`0 4 * * 0 prune_reliability_events.sh`) deletes rows older than 180d. GDPR right-to-be-forgotten: `scripts/forget_source.py <url>` cascades the registry row + all its events in one transaction.

When adding new event types, extend the schema's `event_type` ASSERT enum (`'correct' | 'incorrect' | 'manual_override' | 'init'`) — don't write events with unlisted types, the schema rejects them.

---

## n8n 2.15.x operational notes

These are non-obvious n8n behaviors that broke things during the upgrade and are not in any release notes:

- **`update:workflow` is deprecated → use `publish:workflow`.** The CLI prints a deprecation warning but still works; switch to `publish` for new scripts.
- **Workflow changes do not take effect until n8n restart.** New in 2.15.x. After re-importing/publishing the monolith, always `systemctl --user restart n8n` and re-trigger via webhook before declaring "deployed."
- **`execSync(gemini ...)` blocks the task runner event loop ~40s.** The default `N8N_RUNNERS_HEARTBEAT_INTERVAL=30` kills the runner mid-call. Already mitigated in `~/.config/systemd/user/n8n.service` with `HEARTBEAT_INTERVAL=300` and `TASK_TIMEOUT=600`. Do not lower these.
- **Re-importing a workflow used to strip credentials.** As of commit `8024360` the committed JSON bundles credential bindings, but always run flash mode immediately after a re-import to confirm credentials still resolve.

---

## Workflow modification pattern

Editing a Code node inside the monolith JSON via the `Edit` tool is dangerous — escape sequences (`\n`, `\\`, `\"`) inside the embedded `jsCode` string get mangled. The safe pattern is:

1. Write a small Python patch script in `/tmp/patch_<node>.py` that loads the JSON, mutates the target node's `parameters.jsCode`, and writes it back with `json.dump(..., indent=2)`.
2. Run the patcher.
3. Validate with `python3 -c "import json; json.load(open('workflows/research-orchestrator-monolith.json'))"`.
4. Re-import via `n8n import:workflow --input=...`, `n8n publish:workflow --id=69QGdrWQneaaph5Z`, restart n8n.
5. Smoke-test in this order: **flash → quick → standard**. Flash catches credential breakage cheaply (~1.3s), quick catches the bookkeeping write path, standard exercises the full P3 → reputation → event-emit path.

This is how the `D: Reputation Update` rewrite was deployed safely.

---

## Gemini CLI flag order

`gemini` uses yargs, which treats `-p` as a string option. **`gemini -p -m gemini-2.5-pro "prompt"` fails** with `Not enough arguments following: p` because `-m` gets consumed as the value of `-p`. Always write:

```bash
gemini -m gemini-2.5-pro -p "prompt"
```

All three monolith nodes (`p0-gemini-query-plan`, `p1-gemini-deep`, `p4-gemini-synthesis`) follow this order. Don't reorder them.

---

## Smoke-test ladder (after any monolith change)

| Mode     | Purpose                                  | Time   | Trigger                                                    |
|----------|------------------------------------------|--------|------------------------------------------------------------|
| flash    | Credentials + node-graph integrity       | ~1s    | webhook `mode=flash`                                        |
| quick    | Bookkeeping write path (no P3, no events)| ~1.5m  | webhook `mode=quick`                                        |
| standard | Full P3 + reputation + event emit        | ~4m    | webhook `mode=standard`                                     |
| deep     | + P2 counter-research + Claude synthesis | ~10m+  | webhook `mode=deep` (only when explicitly testing P2)       |

After standard, verify `SELECT count() FROM source_reliability_event GROUP ALL;` increased.

---

## What NOT to do

- Don't `git push` from inside an agent session unless Nico says so this turn.
- Don't add fields to `source_registry` to track reliability — that's what `source_reliability_event` is for.
- Don't bypass `BEGIN/COMMIT TRANSACTION` to "simplify" reputation logic.
- Don't lower the n8n runner heartbeat/task timeout.
- Don't use `n8n update:workflow` in new scripts.
- Don't edit `jsCode` strings in the monolith JSON via `Edit` — use the Python-patch pattern.
- Don't reorder gemini CLI flags.
- Don't trust the 4-day-old `sprint2_context.md` memory's workflow id (`XKDudQuSypLMTQ0P`) — the current monolith id is `69QGdrWQneaaph5Z`.
