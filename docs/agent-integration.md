# Agent Integration Guide

> How OpenClaw, Hive, and humans trigger the research pipeline, handle HITL, and receive results.
> Webhook: `POST http://localhost:5678/webhook/research-start`

---

## Overview

Three trigger sources are supported:

| Source | trigger_source | HITL routing | Result delivery |
|--------|---------------|-------------|----------------|
| OpenClaw (Nathan) | `openclaw` | Callback webhook → agent answers | SurrealDB poll + Telegram |
| Hive multi-agent | `hive` | Callback webhook → agent answers | Paperclip API + Telegram |
| Human (Telegram/Portal) | `telegram`, `portal`, `manual`, `webhook` | Telegram Research Bot (Nico) | Telegram |

---

## 1. OpenClaw Integration

### Default path (n8n — quality gates, Drive, Portal visibility)

```bash
# Via research.py --n8n flag (blocks until result ready)
python3 ~/.openclaw/workspace/scripts/research.py "query" --n8n --mode standard

# Mode options: flash, quick, standard, deep
python3 ~/.openclaw/workspace/scripts/research.py "what version is n8n?" --n8n --mode flash
```

### Direct webhook (non-blocking)

```bash
curl -s -X POST http://localhost:5678/webhook/research-start \
  -H "Content-Type: application/json" \
  -d '{
    "query": "best practices for TypeScript monorepos",
    "mode": "standard",
    "language": "de",
    "trigger_source": "openclaw",
    "run_id": "openclaw_1744300000",
    "callback_webhook": "http://localhost:5678/webhook/research-hitl-response"
  }'
```

Returns immediately: `{ "run_id": "...", "status": "started" }`

### Polling for results (manual)

```bash
curl -s -X POST http://localhost:8001/sql \
  -H "NS: research" -H "DB: workflow" -H "Accept: application/json" \
  --data "SELECT status, report FROM research_run WHERE id = 'openclaw_1744300000';"
```

Poll every 5–15s. Status flow: `running` → `verifying` → `done` / `delivered`

### Fallback path (n8n down)

```bash
python3 ~/.openclaw/workspace/scripts/research.py "query"          # Full stack (Brave+Perplexity+Grok+Tavily)
python3 ~/.openclaw/workspace/scripts/research.py "query" --quick  # Brave + Perplexity only
```

---

## 2. Hive Integration

Hive's `hive-product-research.json` workflow automatically calls `/webhook/research-start` after structuring product requirements.

**What it sends:**
```json
{
  "query": "<structured search queries from Hive>",
  "mode": "standard",
  "domain_hint": "product_comparison",
  "trigger_source": "hive",
  "run_id": "hive_<projectId>_<timestamp>",
  "callback_webhook": "http://localhost:5678/webhook/hive-research-done"
}
```

**Completion callback:** When research finishes, n8n POSTs to `/webhook/hive-research-done` (handled by `hive-research-callback.json`), which writes the result summary to Paperclip API at `/api/research/<run_id>/result`.

---

## 3. HITL — Human-in-the-Loop

HITL fires when:
- Confidence < 75% after verification
- High-stakes domain (finance, legal, security)
- Contradictions between sources that cannot be auto-resolved

### Routing by trigger_source

| trigger_source | HITL goes to |
|---------------|-------------|
| `openclaw`, `hive` | POST to `callback_webhook` URL |
| `portal`, `telegram`, `webhook`, `manual` | Telegram Research Bot (Nico gets inline buttons) |

### HITL payload (to agent's callback_webhook)

```json
{
  "run_id": "openclaw_1744300000",
  "type": "hitl_question",
  "question": "Source A claims X, Source B claims Y. Which should we trust?",
  "report_preview": "...",
  "approve_url": "http://localhost:5678/webhook/research-hitl-response"
}
```

### Agent response

```bash
curl -s -X POST http://localhost:5678/webhook/research-hitl-response \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": "openclaw_1744300000",
    "approved": true,
    "answer": "Source A is T1 tier (official docs). Approve.",
    "trigger_source": "openclaw"
  }'
```

**Agent decision rules:**
- Source credibility / contradiction → decide autonomously (T1/T2 = approve)
- High-stakes finance/legal → escalate to Nico once, wait, then POST decision
- Factual ambiguity with T1/T2 sources → default approve

**Reject + rewrite:**
```json
{
  "run_id": "...",
  "approved": false,
  "edited_query": "revised query with clearer scope",
  "answer": "Query was too broad — narrowed to specific framework version"
}
```

---

## 4. Mode Selection

| Mode | Use case | LLM calls | Cost | Time |
|------|---------|-----------|------|------|
| `flash` | Single fact, version, URL | 0 | ~$0 | <10s |
| `quick` | Brief comparison, how-to | 2 (Gemini) | ~$0.02 | <2min |
| `standard` | Best practices, tooling, content | 4-6 | ~$0.50 | 5-15min |
| `deep` | Architecture, finance, legal, security | 8-12 | ~$1-3 | 15-30min |

**Auto-classification** (Phase 0) detects mode from query content. Override with `[flash]`, `[quick]`, `[standard]`, or `[deep]` anywhere in the query string.

See `docs/research-modes.md` for full reference.

---

## 5. Webhook Payload Reference

```json
POST http://localhost:5678/webhook/research-start
Content-Type: application/json

{
  "query": "string (required)",
  "mode": "flash | quick | standard | deep (optional, default: standard)",
  "language": "de | en (optional, default: de)",
  "trigger_source": "openclaw | hive | portal | telegram | webhook | manual (optional)",
  "domain_hint": "tech | finance | academic | product_comparison | general (optional)",
  "run_id": "string (optional, auto-generated if omitted)",
  "callback_webhook": "http://... (optional, required for agent HITL routing)"
}
```

---

## 6. New Workflows Added (2026-04-10)

| Workflow | Path | Purpose |
|----------|------|---------|
| `research-hitl-response` | `workflows/research-hitl-response.json` | Agent HITL answer webhook — receives approved/rejected, updates SurrealDB |
| `hive-research-callback` | `hive/hive-company/n8n/workflows/hive-research-callback.json` | Receives completed Hive research, POSTs to Paperclip |

Both need to be imported into live n8n and tagged/foldered via `scripts/organize-workflows.py`.
