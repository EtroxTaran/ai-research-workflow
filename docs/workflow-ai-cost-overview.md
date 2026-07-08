# Workflow AI & Cost Node Overview

> Generated: 2026-04-15 | Total workflows: 25 | **AI-cost workflows: 3**

Use this as the entry point for cost reviews. Workflows marked **YES** spawn external AI API calls and accumulate token costs. Everything else is deterministic routing/logic — no token spend.

---

## TL;DR — What costs money

| # | Workflow | ID | Trigger | Models | Call Pattern | Cost Level |
|---|----------|----|---------|--------|--------------|------------|
| 1 | **Research Pipeline MVP** | `69QGdrWQneaaph5Z` | Manual / Webhook | Gemini + Claude | CLI `execSync` | 🔴 HIGH |
| 2 | **Research Creator Discovery** | `TMg2GpvBwSIEQIqA` | Schedule `0 2 * * *` | Gemini | CLI `execSync` | 🟡 MEDIUM |
| 3 | **Research Weekly Digest** | `72CMlkiGvzcLQ5Yv` | Schedule `0 8 * * 0` | Gemini | CLI `execSync` | 🟢 LOW |

---

## Detailed AI Node Breakdown

### 1. Research Pipeline MVP (`research-orchestrator-monolith.json`)

**4–5 AI calls per full run** depending on mode (flash/quick/standard/deep).

| Node | Model | CLI Call | Triggered in |
|------|-------|----------|-------------|
| P0: Gemini Query Plan | Gemini | `execSync('gemini -m gemini-2.5-pro -p "..."')` | standard, deep |
| P1: Gemini Deep Search | Gemini | `execSync('gemini -m gemini-2.5-pro -p "..."')` | standard, deep |
| P2: Devil's Advocate | Claude | `execSync('claude ...')` | deep only |
| P4: Claude CLI Synthesis | Claude | `execSync('claude ...')` | standard, deep |
| P4: Gemini CLI Synthesis | Gemini | `execSync('gemini -m gemini-2.5-pro -p "..."')` | standard, deep |

**Cost controls already in place:**
- `mode=flash` → no AI calls (credential + graph check only)
- `mode=quick` → no AI calls (bookkeeping write path)
- P2 (Claude Devil's Advocate) only runs on `mode=deep`
- No automatic/scheduled trigger — always manually or webhook-initiated

**Review focus:** Token limits per node, prompt length, whether P1 deep search justifies cost vs. quick mode.

---

### 2. Research Creator Discovery (`research-creator-discovery.json`)

**1 AI call per run**, runs nightly at 02:00.

| Node | Model | CLI Call |
|------|-------|----------|
| Classify with Gemini | Gemini | `execSync('gemini -p "Classify these domains..."')` |

**Review focus:** How many domain candidates are classified per run? Prompt length scales with input list. Consider batching or filtering before the Gemini call.

---

### 3. Research Weekly Digest (`research-weekly-digest.json`)

**1 AI call per run**, weekly on Sundays at 08:00.

| Node | Model | CLI Call |
|------|-------|----------|
| Generate Digest Summary | Gemini | `execSync('gemini ...')` (piped summary prompt) |

**Review focus:** Digest input size. If the weekly research accumulation is large, this can be a big context window.

---

## Call Pattern: All CLI via `execSync`

None of the workflows use:
- n8n native AI nodes (`@n8n/n8n-nodes-langchain.*`)
- OpenAI/Anthropic NPM SDK inside Code nodes
- Direct HTTP requests to `api.anthropic.com` or `api.openai.com`

All AI calls go through CLI binaries (`gemini`, `claude`) reading keys from `~/.openclaw/.env`. This means:
- **Token usage is NOT tracked inside n8n** — it only shows up in Google AI Studio / Anthropic Console billing dashboards
- No per-execution cost logging in the workflow itself (outside of `hive-cost-reporter` which tracks Hive-scoped costs separately)

---

## Non-AI Workflows (Safe, No Token Spend)

These 22 workflows have zero AI API calls — all deterministic routing, logic, or data movement.

| Workflow | ID | Trigger | Purpose |
|----------|----|---------|---------|
| KB RSS Ingest | `kb-rss-ingest-1` | Schedule `08:30 daily` | Miniflux RSS → SurrealDB |
| KB Webhook URL Submit | `kb-webhook-ingest-1` | Webhook | Manual URL → SurrealDB |
| Hive - Research Callback | `64JclkzS1DnW6pGr` | Webhook | Result callback router |
| Hive - Scout Failover Watchdog | `dX5wsM4NLkSEHv05` | Webhook | Failover detection |
| Hive - Notification Router | `Vv0jlkYJCMnfkN83` | Webhook | Event notifications |
| Hive - Architecture Evaluator | `0jSgDJmQ2jVevrN5` | Webhook | Deterministic arch scoring |
| Hive - Auto-Review Trigger | `s52ae4UHrVUiMTlK` | Webhook | Review qualification |
| Hive - Correction Router | `EKTLqWKi3w9RvDxF` | Webhook | Review feedback routing |
| Hive - Cost Reporter | `RWppN4c34UK70MMQ` | Webhook | Cost aggregation + alerts |
| Hive - Creative Divergence | `cjXs4VxtgiF9QJaP` | Webhook | Vision scoring (deterministic) |
| Hive - Gate Evaluator | `gMm8bKjFy722Q0kb` | Webhook | Gate validation |
| Hive - Health Monitor | `rfqdv7Q4nEhnemPY` | Webhook | System health checks |
| Hive - Pipeline Advancer | `8ncQpfVxJCj1sM3A` | Webhook | Workflow state advancement |
| Hive - Product Research | `b23HHqMeMu4ZP1jz` | Webhook | Product evaluation |
| Hive - Rate Limit Failover | `vUo73JHgtThGbXAv` | Webhook | Rate limit error handling |
| Hive - Retrospective Analyzer | `emlKf2JJbtS3wLFo` | Webhook | Analysis + reporting |
| Hive - Security Scanner | `jOboCnk65YqILzW4` | Webhook | Security evaluation |
| Hive - Specialist Coverage | `siTpZ5GJ1eIY0WAN` | Webhook | Agent coverage check |
| Hive - Tech Stack Resolver | `qTtokH57tUDc24Ag` | Webhook | Tech selection logic |
| Research Continuous Monitor | `yRsHld8Yfi7I4WzA` | Schedule `*/6h` | SurrealDB monitoring (Brave Search API, not LLM) |
| Research Feedback Handler | `63h9DuPDCwuxAZZD` | Webhook | Reputation + event DB writes |
| Research HITL Response | `ghzLn4jf6buFCtk8` | Webhook | Agent callback handler |

> **Note:** Research Continuous Monitor uses Brave Search API (external, paid per query) but not LLM inference — consider it in API cost reviews but not token cost reviews.

---

## Review Checklist

For each AI workflow, verify:
- [ ] Prompt sizes are bounded (not unbounded data piped in)
- [ ] Rate limiting or circuit breaker exists for failure loops
- [ ] Costs are visible somewhere (Anthropic Console / Google AI Studio billing)
- [ ] Mode gates work correctly (flash/quick skip AI calls)
- [ ] No accidental parallel execution risk (webhook + schedule firing simultaneously)
