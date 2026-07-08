# Research Pipeline — PRODUCTION (Native) — Updated 2026-04-10

## Status
Pipeline laeuft nativ als systemd User-Service auf B-Link R2D2. Alle CLIs (Claude, Gemini, Codex) nativ verfuegbar.

### Runtime
- **n8n**: Nativ als `systemctl --user` Service, Port 5678
- **CLIs**: Claude v2.1.92, Gemini v0.32.1, Codex v0.112.0, Python 3.12.3 — alle nativ
- **SurrealDB**: Docker Container, `localhost:8001` (`research/workflow` Namespace)
- **MiniFlux**: Docker Container, `localhost:8070`
- **Telegram**: Research Bot Webhook via Tailscale Funnel (`https://r2d2.example-net.ts.net:8443`)

### Service Management
```bash
systemctl --user status n8n     # Status
systemctl --user restart n8n    # Neustart
systemctl --user stop n8n       # Stoppen
journalctl --user -u n8n -f     # Logs
```

### n8n UI over HTTP (LAN / Tailscale)
Browser login uses cookies. By default n8n sets `Secure` cookies (`N8N_SECURE_COOKIE=true`), which browsers **do not send** on plain `http://`. For trusted LAN or Tailscale without TLS in front of n8n, the user service sets `N8N_SECURE_COOKIE=false` in `~/.config/systemd/user/n8n.service`. If you terminate TLS (reverse proxy), set it back to `true` and use `https` in `WEBHOOK_URL` / `N8N_EDITOR_BASE_URL` as needed.

**Instance-level MCP (bulk):** To set **Available in MCP** on every eligible workflow via the internal REST API, use [`scripts/enable-n8n-mcp-workflows.sh`](./scripts/enable-n8n-mcp-workflows.sh): set `N8N_AUTH_COOKIE` and **`N8N_BROWSER_ID`** (same tab: Console → `localStorage.getItem('n8n-browserId')`, or Network → `/rest/` request → header `browser-id`) (`--dry-run` first).

**Cursor MCP (URL + token + verify):** [docs/n8n-mcp-cursor-setup.md](./docs/n8n-mcp-cursor-setup.md), [`./scripts/verify-n8n-mcp.sh`](./scripts/verify-n8n-mcp.sh), template [`env.n8n-mcp.example`](./env.n8n-mcp.example).

### Workflows (25 total — DEPLOYED)
| Workflow | ID | Typ |
|---|---|---|
| Research Orchestrator Monolith | `69QGdrWQneaaph5Z` | Webhook `research-start` — 53 Nodes, 4 Modi |
| Research Weekly Digest | `72CMlkiGvzcLQ5Yv` | Cron: Sonntag 08:00 |
| Research Feedback Handler | `63h9DuPDCwuxAZZD` | Webhook `research-feedback` |
| Research Continuous Monitor | `yRsHld8Yfi7I4WzA` | Cron: alle 6h |
| Research HITL Response (Agent Callback) | `ghzLn4jf6buFCtk8` | Webhook `research-hitl-response` — agent HITL |
| KB RSS Ingest | `kb-rss-ingest-1` | — |
| KB Webhook URL Submit | `kb-webhook-ingest-1` | — |
| + 16 Hive workflows | — | Active |
| Hive - Research Callback | dynamic | Webhook `hive-research-done` — Paperclip write |

### n8n Folder Structure (3 folders)
| Folder | Workflows | Tag |
|---|---|---|
| Research | 6 research workflows | `research` |
| Hive | 16 Hive workflows | `hive` |
| KB | 2 KB ingest workflows | `kb` |

### 4 Research Modes (flash/quick/standard/deep)
| Mode | Nodes used | LLMs | Cost | Time |
|---|---|---|---|---|
| `flash` | flash-if-mode → flash-brave-search → flash-deliver | 0 | ~$0 | <10s |
| `quick` | Full orchestrator, Phases 0+1+4 only | 2 Gemini | ~$0.02 | <2min |
| `standard` | Phases 0-4, 6 branches, Gates 1+3+4 | 4-6 | ~$0.50 | 5-15min |
| `deep` | Phases 0-4, all 7 branches, all 4 gates, HITL | 8-12 | ~$1-3 | 15-30min |

### Agent Integration (NEW 2026-04-10)
- **OpenClaw**: `python3 research.py "query" --n8n --mode standard` (polls SurrealDB, returns report)
- **Hive**: `hive-product-research.json` auto-triggers `/webhook/research-start` after structuring requirements
- **HITL loop**: agent sources → callback_webhook → agent answers via `/webhook/research-hitl-response`
- **Web UI**: `portal/index.html` (static, open in browser — POSTs to n8n, polls SurrealDB for status)

### Deployment Status (2026-04-10) — COMPLETE
- [x] 4 workflows imported/updated via `n8n import:workflow` (monolith 53 / HITL 6 / hive-product-research 9 / hive-research-callback 5)
- [x] `organize-workflows.py` extended with `NEW_WORKFLOWS_BY_NAME` resolver — 25 workflows assigned to Hive/Research/KB folders + tags
- [x] Credential bindings repaired on monolith (7 HTTP nodes) + HITL response (1 HTTP node) — n8n CLI strips credentials on import, patched directly in `workflow_history` for active version + persisted into committed JSONs to prevent regression
- [x] HITL response: auth corrected to `httpBasicAuth`, headers `surreal-ns`/`surreal-db` (lowercase) for SurrealDB 2.x
- [x] `research.py` polling fixed: lowercase headers, `WHERE run_id=...`, accepts `done|delivered|completed`, falls back to `research_report.content_markdown` via `type::record('research_run:<id>')`, `trigger_source=manual` to bypass HITL Agent Callback branch
- [x] Smoke 5a (flash <10s) — exec 774, ✅
- [x] Smoke 5b (`research.py --n8n --mode quick`) — returns full markdown report ✅
- [x] Smoke 5c (HITL webhook) — POST returns 200, exec 796 success ✅
- [x] Smoke 5d (quick mode regression) — covered by execs 781/786/788/789 ✅
- [x] Smoke 5e (folder structure) — Research/Hive/KB folders populated ✅

### Trigger
```bash
curl -X POST http://localhost:5678/webhook/research-start \
  -H "Content-Type: application/json" \
  -d '{"query": "...", "mode": "quick|standard|deep", "trigger_source": "manual"}'
```

### Migration von Docker
n8n lief zuvor als Docker Container (`n8n-local`). Migration auf nativ wegen:
- Claude CLI (glibc Binary) lief nicht in Alpine-Container
- Dateiberechtigungen (.openclaw) erforderten komplexe Mount-Strategien
- Alle Workflow-Pfade waren fuer Host-Ausfuehrung designed (`/home/clawd/...`)

Docker Compose + Dockerfile bleiben als Fallback unter `~/containers/n8n/`.
