---
name: research-workflow
description: Triggers the n8n AI Research Pipeline on localhost:5678 for structured multi-source research with quality gates and HITL. Use when asked to research, recherchiere, analyze, compare, or investigate any topic. Supports flash (instant lookup), quick (2min), standard (15min), deep (30min) modes. Handles HITL questions autonomously for agent triggers. NOT for: real-time chat, code generation, file operations, system admin, editing n8n JSONs.
---

# Skill: research-workflow

## Description

Triggers the n8n AI Research Pipeline for multi-source research with quality gates, verification, and adaptive modes. Results delivered via Telegram Research Bot and SurrealDB. For agent-triggered research (OpenClaw), the pipeline POSTs HITL questions to a callback webhook which this skill handles.

**Trigger phrases:** "recherchiere", "research", "untersuche", "analysiere", "vergleiche X vs Y", "was ist der Stand zu", "finde heraus", "research [topic]", any question requiring web lookup or structured analysis

**NOT for:** real-time conversational questions, code generation, file operations, system administration, implementing research logic directly (always delegate to n8n), editing production n8n JSONs without backup

---

## Mode Selection (REQUIRED — choose before triggering)

| Mode | When to use | Examples | Cost | Time |
|------|------------|---------|------|------|
| `flash` | Single fact, version, URL, yes/no | "current n8n version?", "what port does SurrealDB use?" | ~$0 | <10s |
| `quick` | Brief comparison or how-to | "compare X vs Y briefly", "how do I do Z?" | ~$0.02 | <2min |
| `standard` | Best practices, content, tooling | "best practices for X", "which creator covers Y?" | ~$0.50 | 5-15min |
| `deep` | Architecture, finance, legal, tax | "should we use X architecture?", "tax implications of..." | ~$1-3 | 15-30min |

**Decision rule:**
- Single fact / version number → `flash`
- Multi-source comparison needed but not critical → `quick`
- Professional decision requiring current sources → `standard`
- High-stakes: financial, legal, architectural, security → `deep`

User can force mode by including `[flash]`, `[quick]`, `[standard]`, or `[deep]` in the query.

---

## Action

### Option A: Via n8n (DEFAULT — use this)

```bash
# Standard research
curl -s -X POST http://localhost:5678/webhook/research-start \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{{RESEARCH_QUERY}}",
    "mode": "{{MODE: flash|quick|standard|deep}}",
    "domain_hint": "{{DOMAIN: tech|finance|academic|product_comparison|general}}",
    "language": "{{de|en}}",
    "trigger_source": "openclaw",
    "run_id": "openclaw_{{TIMESTAMP}}",
    "callback_webhook": "{{AGENT_CALLBACK_URL_IF_HITL_EXPECTED}}"
  }'

# OR via Python script with n8n flag (auto-polls for result)
python3 ~/.openclaw/workspace/scripts/research.py "{{QUERY}}" --n8n --mode {{MODE}}
```

The webhook returns immediately with `{ "run_id": "...", "status": "started" }`. Results arrive via:
- **Telegram** Research Bot (async) — always
- **SurrealDB** `research/workflow` namespace — query for results
- **Google Drive** `Familie/Research/` — for standard/deep

### Option B: Direct APIs (FALLBACK — only when n8n is down)

```bash
python3 ~/.openclaw/workspace/scripts/research.py "{{QUERY}}"          # Full stack
python3 ~/.openclaw/workspace/scripts/research.py "{{QUERY}}" --quick  # Brave + Perplexity
```

---

## Polling for Results (n8n path)

When using `--n8n` flag, research.py automatically polls and returns the report text when done:

```bash
python3 ~/.openclaw/workspace/scripts/research.py "query" --n8n --mode standard
# Blocks until result ready, then prints report to stdout
```

Or manually poll SurrealDB:
```bash
curl -s -X POST http://localhost:8001/sql \
  -H "NS: research" -H "DB: workflow" -H "Accept: application/json" \
  --data "SELECT status, report FROM research_run WHERE id = '{{RUN_ID}}';"
```

---

## HITL Handling (Agent-Triggered Research)

When research triggers HITL (confidence <75%, high-stakes domain, contradictions), n8n POSTs to `callback_webhook`:

```json
{
  "run_id": "...",
  "type": "hitl_question",
  "question": "...",
  "report_preview": "...",
  "approve_url": "http://localhost:5678/webhook/research-hitl-response"
}
```

**Agent response rules:**
- Source trust / contradiction → decide autonomously using context, approve with `approved: true`
- High-stakes finance/legal → escalate to Nico ONCE, wait for response, then POST decision
- Factual ambiguity → default to approve if sources are T1/T2 tier

**Respond to HITL:**
```bash
curl -s -X POST http://localhost:5678/webhook/research-hitl-response \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": "{{RUN_ID}}",
    "approved": true,
    "answer": "Approved — sources are credible T1/T2 tier",
    "trigger_source": "openclaw"
  }'
```

---

## Response to User

After triggering (non-flash modes):
> "Research-Auftrag gestartet (Modus: {{MODE}}, ~{{TIME}}). Report kommt über Research Bot. Run-ID: {{RUN_ID}}"

After flash mode (immediate):
> Present the bullet list results directly from the response.

---

## Parameters Reference

| Field | Required | Values | Default |
|-------|----------|--------|---------|
| `query` | yes | Natural language string | — |
| `mode` | no | `flash`, `quick`, `standard`, `deep` | `standard` |
| `language` | no | `de`, `en` | `de` |
| `trigger_source` | no | `openclaw`, `hive`, `portal`, `webhook` | `webhook` |
| `domain_hint` | no | `tech`, `finance`, `academic`, `product_comparison`, `general` | auto |
| `run_id` | no | Custom ID string | `run_{{timestamp}}` |
| `callback_webhook` | no | URL for HITL callbacks | — |

---

## Full Reference

See `/home/clawd/projects/research-workflow-n8n/docs/research-modes.md` for complete mode table, source branches per mode, and verification stages.
