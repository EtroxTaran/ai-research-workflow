# Research Modes — Canonical Reference

> This is the authoritative mode reference for all agents (OpenClaw, Hive) and humans.
> Webhook: `POST http://localhost:5678/webhook/research-start`

---

## Mode Overview

| Mode | LLM calls | Est. cost | Time | Gates | HITL |
|------|-----------|-----------|------|-------|------|
| `flash` | 0 | ~$0 | <10s | None | Never |
| `quick` | 2 (Gemini) | ~$0.02 | <2min | Gate 4 only | Never |
| `standard` | 4-6 | ~$0.50 | 5-15min | Gates 1, 3, 4 | Rarely |
| `deep` | 8-12 | ~$1-3 | 15-30min | All 4 gates | Often |

---

## When to Use Each Mode

### `flash` — Just Google It

**Use when:** You need a quick fact, version number, URL, or single-sentence answer.

Examples:
- "What is the current stable version of n8n?"
- "Which npm package handles JWT in Node.js?"
- "What port does SurrealDB use by default?"
- "Who is the CEO of Anthropic?"

**How it works:** Single Brave Search call → top 5 results formatted as bullet list → delivered immediately. No LLM synthesis, no phases, no verification.

**Trigger:** Include `[flash]` in query, set `"mode": "flash"` in payload, or leave auto-classification to detect single-fact queries.

---

### `quick` — Fast Comparison or How-To

**Use when:** You need a brief multi-source answer but don't need depth or verification.

Examples:
- "Compare React vs Svelte for a small project"
- "How do I set up a Docker volume mount?"
- "Quick summary of what LangGraph does"
- "What are the main differences between SurrealDB and PostgreSQL?"

**How it works:** Brave + Tavily web search → Gemini synthesis (2 calls) → no verification → Telegram delivery.

**Trigger:** Include `[quick]` in query, or set `"mode": "quick"`.

---

### `standard` — Best Practices, Content, Tooling

**Use when:** You need a thorough, multi-perspective answer for a professional decision.

This is the **default mode** when no mode is specified.

Examples:
- "Which content creators cover n8n best practices in 2026?"
- "Best practices for TypeScript monorepo structure"
- "Compare managed Kubernetes options for a small SaaS"
- "What are the current patterns for React Server Components?"
- "Which CLI tools are best for AI-assisted coding workflows?"

**How it works:** 6 parallel search branches (KB, Web, Gemini Deep, Social/Grok, Academic, MiniFlux RSS) → Gemini synthesis → CoVe verification + LLM Judge → quality gates 1, 3, 4 → Telegram + Drive + SurrealDB.

**Trigger:** Default, or set `"mode": "standard"`.

---

### `deep` — Architecture, Finance, Legal, High-Stakes

**Use when:** The decision has significant consequences and requires maximum rigor, counter-arguments, and verification.

Examples:
- "Should we migrate our database from PostgreSQL to SurrealDB?"
- "Financial planning: how should we structure income from a GmbH vs. freelance in Germany?"
- "Architecture decision: monolith vs microservices for our next product"
- "What are the tax implications of cryptocurrency gains for German residents in 2026?"
- "Security audit approach for a B2B SaaS product handling medical data"

**How it works:** All 7 search branches + counter-research (Claude Opus Devil's Advocate) + full verification (CoVe + FActScore + LLM Judge) → all 4 quality gates → HITL if confidence <75% or high-stakes domain → Claude Opus synthesis → Telegram + Drive + SurrealDB.

**Trigger:** Include `[deep]` in query, or set `"mode": "deep"`.

---

## Auto-Classification (Phase 0)

If no mode is specified, Gemini auto-classifies based on:

| Signal | → Mode |
|--------|--------|
| Single noun/verb lookup, "what is X", version queries | `flash` |
| Brief comparison, "how to", tool summary | `quick` |
| Best practices, content creators, tooling, multi-source | `standard` |
| Finance, legal, tax, architecture, security, "should we" | `deep` |

To override: add `[flash]`, `[quick]`, `[standard]`, or `[deep]` anywhere in the query string.

---

## Webhook Payload

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
  "callback_webhook": "http://... (optional, for agent HITL callbacks)"
}
```

### Trigger Source — HITL Routing

| `trigger_source` | HITL goes to |
|-----------------|-------------|
| `openclaw`, `hive` | `callback_webhook` URL (agent handles it) |
| `portal`, `telegram`, `webhook`, `manual` | Telegram Research Bot (Nico) |

If `trigger_source` is `openclaw` or `hive` and HITL fires, n8n POSTs the question to `callback_webhook`. The agent must respond via `POST http://localhost:5678/webhook/research-hitl-response` with:

```json
{
  "run_id": "...",
  "approved": true,
  "answer": "optional explanation",
  "edited_query": "optional new query if rejecting"
}
```

---

## CLI Usage (OpenClaw)

```bash
# Via n8n (recommended — quality gates, Drive storage, Portal visibility)
python3 ~/.openclaw/workspace/scripts/research.py "query" --n8n --mode standard

# Direct APIs (fallback when n8n is down)
python3 ~/.openclaw/workspace/scripts/research.py "query" --quick

# Mode shortcuts
python3 ~/.openclaw/workspace/scripts/research.py "query" --n8n --mode flash
python3 ~/.openclaw/workspace/scripts/research.py "query" --n8n --mode deep
```

---

## Source Branches by Mode

| Branch | flash | quick | standard | deep |
|--------|-------|-------|----------|------|
| A: KB (SurrealDB) | ✗ | ✗ | ✓ | ✓ |
| B: Web (Brave+Tavily) | ✓ (Brave only) | ✓ | ✓ | ✓ |
| C: Gemini Deep Search | ✗ | ✗ | ✓ | ✓ |
| D: Social/Grok X Search | ✗ | ✗ | ✓ | ✓ |
| E: Academic (Semantic Scholar) | ✗ | ✗ | ✓ | ✓ |
| F: MiniFlux RSS | ✗ | ✓ | ✓ | ✓ |
| G: You.com Deep Research | ✗ | ✗ | ✗ | ✓ |

---

## Verification Stages by Mode

| Stage | flash | quick | standard | deep |
|-------|-------|-------|----------|------|
| Gate 1 (source count) | ✗ | ✗ | ✓ ≥8 | ✓ ≥12 |
| Gate 2 (counter-research) | ✗ | ✗ | ✗ | ✓ ≥80% |
| Gate 3 (CoVe + Judge) | ✗ | ✗ | ✓ ≥70% | ✓ ≥80% |
| Gate 4 (structure) | ✗ | ✗ | ✓ | ✓ |

---

*Last updated: 2026-04-10 | Source of truth: `workflows/research-orchestrator-monolith.json`*
