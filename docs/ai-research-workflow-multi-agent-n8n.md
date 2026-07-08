# The Perfect AI Research Workflow
## Multi-Agent n8n Architecture with Verification, Validation & Knowledge Base

***

## Executive Summary

This report designs a best-in-class, fully automated research workflow built on **n8n** with a multi-provider LLM stack (OpenAI GPT-5, Claude 4.5, Gemini 3, and Grok 4), specialized research agents, structured quality gates, adversarial validation, and an end-to-end knowledge base pipeline into Notion/Obsidian. The system handles any research domain — finance, software architecture, vacation planning, social trends — by decomposing queries into parallel sub-tasks, executing them through domain-specialized agents, verifying results through an independent validator and a Red Team challenger, and only graduating sources that survive scrutiny into the final knowledge base.

The design is grounded in the **VMAO (Verified Multi-Agent Orchestration)** framework, Anthropic's production orchestrator-worker pattern, and best practices from the n8n production deployment guide.[^1][^2][^3][^4][^5][^6]

***

## Part 1: Foundational Architecture

### The Orchestrator-Worker Pattern

The backbone of best-in-class multi-agent research is the **orchestrator-worker (hub-and-spoke) architecture**. A lead orchestrator agent decomposes the research query, assigns sub-tasks to specialized workers operating in parallel, collects their outputs, and routes them through verification before synthesis. This pattern was independently validated by Anthropic's production Research system, which demonstrated that parallel subagents acting as "intelligent filters" dramatically outperform single-agent research.[^7][^2]

The key insight from the VMAO research framework is the five-phase loop: **Plan → Execute → Verify → Replan → Synthesize**. Queries are broken into a Directed Acyclic Graph (DAG) of sub-questions with dependency-aware parallel execution. A dedicated verifier evaluates completeness and triggers replanning when gaps are identified, looping until a configurable stop condition is met (e.g., completeness score > 0.8 or a maximum of 3 iterations). This approach improved answer completeness from 3.1 to 4.2 and source quality from 2.6 to 4.1 (on a 1–5 scale) compared to single-agent baselines.[^4][^5]

### Three-Tier Agent Taxonomy

Agents are organized into three functional tiers that reflect the natural information flow:[^4]

| Tier | Function | Agents |
|------|----------|--------|
| **Tier 1 — Data Gathering** | Retrieve raw information from all source types | Web Agent, Academic Agent, Social Agent, YouTube Agent, Creator Monitor Agent |
| **Tier 2 — Analysis** | Reason over gathered data, extract insights | Domain Analyst, Cross-Source Synthesizer, Devil's Advocate (Red Team) |
| **Tier 3 — Output** | Produce final deliverables and persist to knowledge base | Report Writer, Source Validator, Knowledge Base Exporter |

***

## Part 2: The LLM Stack

Different agents should run different models based on their task profile. Using GPT-4o-mini for narrow repetitive tasks (scraping, classification) versus a frontier model for orchestration reduces total per-run cost by roughly 65%.[^8]

### Model Assignments

| Model | Role in Workflow | Strengths |
|-------|-----------------|-----------|
| **GPT-5.1 / o3** | Orchestrator, Planner, final Synthesizer | Controllable reasoning depth via Thinking Mode; best for headless planning in complex domains[^9]; cached input pricing offers 90% discounts for repeated context in agentic loops[^9] |
| **Claude 4.5 Opus** | Domain Analyst, Report Writer, Verifier | Best for coding, structured tasks, safe enterprise outputs; outperforms on rigorous benchmarks and long-task execution[^10]; 200K context window handles large documents[^11] |
| **Gemini 3 / 2.5 Pro** | Academic Research Agent, Long-Document Processor | Best overall benchmark performance; 1M–2M token context ideal for large corpora of papers[^12][^10]; excels at long-form reasoning and multimodal inputs |
| **Grok 4** | Social Media Agent, Real-Time Trends Agent | Native multi-agent architecture with Harper sub-agent accessing ~68M English tweets/day via X firehose for millisecond-level real-time grounding[^13]; built-in DeepSearch for multi-step research with live citations[^14][^15] |
| **GPT-4o-mini** | Web Scraper Agent, Classification, Deduplication | Near-identical performance to frontier models on narrow structured extraction at ~10× lower cost[^8] |

### Integrating Grok 4 in n8n

Grok 4 is available as a native **xAI Grok Chat Model** node in n8n. Since xAI uses an OpenAI-compatible API format, it can also be configured via the OpenAI node pointing to `x.ai/api`. To enable real-time search, pass `search_parameters: {mode: "auto"}` in the request body. This unlocks Grok's DeepSearch capability — particularly valuable for social sentiment, breaking news, and X/Twitter trend research where recency is critical.[^16][^17][^18]

***

## Part 3: Specialized Research Agents

### 3.1 Web Research Agent

**Model:** GPT-4o-mini (scraping) + Claude 4.5 (synthesis)  
**Tools in n8n:**

- **Tavily Search Tool** — agent-optimized real-time web search with domain filters, time ranges, and topic filters; official n8n integration available[^19][^20]
- **Firecrawl** — full-page content extraction with autonomous Agent endpoint for multi-hop research; flat-rate pricing predictable for production[^21][^22]
- **Exa** — semantic neural search for discovery; pairs well with Firecrawl for extraction[^21]
- **SerpAPI** — Google/Bing SERP results with organic, FAQ, and related query extraction[^23][^24]
- **Perplexity Sonar API** — conversational multi-hop research with built-in citations[^25][^21]

**Process:** Query → parallel Tavily + Firecrawl + SerpAPI calls → deduplicate URLs → extract full content → score by source credibility → return structured JSON to orchestrator.

### 3.2 Academic Research Agent

**Model:** Gemini 2.5 Pro (large context for PDFs) + GPT-5.1 (query decomposition)  
**Tools in n8n:**

- **Semantic Scholar API** — accesses 200M+ academic papers with paper relevance search, citation networks, author profiles, SPECTER embeddings, and 23 discipline filters; supports DOI, arXiv ID, PubMed ID lookups[^26][^27]
- **ArXiv API** — preprint papers, critical for AI/ML topics (HTTP Request node)
- **OpenAlex API** — 250M+ open scholarly works (HTTP Request node)[^28]
- **CrossRef** — citation verification and DOI resolution[^29]

**Process:** Topic → LLM-guided decomposition into search queries → multi-granularity retrieval across APIs → semantic deduplication → citation verification against CrossRef + ArXiv → relevance scoring → abstract + key findings extraction.

The AutoResearchClaw pipeline (open-source, 23-stage) demonstrates a 4-layer citation verification system that cross-checks all references against ArXiv, CrossRef, DataCite, and an LLM judge — directly targeting hallucinated citations.[^30][^29]

### 3.3 Social Media Research Agent

**Model:** Grok 4 (X/Twitter, real-time) + GPT-4o-mini (structured extraction)  
**Tools in n8n:**

- **Apify** — most complete social scraping suite; actors available for LinkedIn, Instagram, TikTok, Reddit, Facebook, YouTube comments, and Google[^31][^32][^33]
- **ScrapeCreators** — single cheap API for 9 platforms (Google, Meta, LinkedIn, Reddit, and more) via one n8n HTTP node[^34][^35]
- **Grok 4 with DeepSearch** — real-time X/Twitter sentiment, trends, influencer posts[^13][^14]
- **Google Trends** — via HTTP Request node to Trends API[^36]

**Platform-Specific Actors (Apify):**
- LinkedIn: posts, profile data, company pages
- Instagram: posts, reels, hashtags, follower counts
- YouTube: channel data, comments, transcripts
- Reddit: subreddit threads, sentiment, upvotes
- TikTok: trending content, creator profiles

### 3.4 YouTube Research Agent

**Model:** Gemini 2.5 Pro (video transcription, long content) + GPT-4o-mini (scoring)  
**Tools in n8n:**

- **YouTube Data API v3** — official node; fetches channel IDs, video metadata, view counts, like counts[^37]
- **Apify YouTube Transcript Actor** — extracts full video transcripts, bypasses YouTube scraping limits[^38][^39][^40]
- **n8n YouTube Channel Monitor Template (#9268)** — ready-made workflow that polls channels from Google Sheets, transcribes with Gemini, scores relevance 1–10, saves to Google Sheets[^37]

**Process:** Trusted Creator List (Google Sheets) → Schedule Trigger (hourly/daily) → YouTube API fetch recent videos per channel → duplicate check → Apify transcript extraction → Gemini transcription + AI summary (500 words) → relevance score 1–10 based on topic criteria → save to Knowledge Base → flag high-relevance for human review.

### 3.5 Trusted Content Creator Monitor Agent

This is a dedicated **always-on monitoring sub-workflow** — separate from ad-hoc research runs — that continuously watches a curated list of trusted creators across all platforms.

**Creator Registry (Google Sheets / Notion Database):**

| Field | Description |
|-------|-------------|
| `creator_id` | Unique identifier |
| `name` | Creator/publication name |
| `platform` | YouTube / X / LinkedIn / Substack / Reddit / Blog |
| `channel_url` | Profile/channel URL |
| `rss_feed_url` | RSS URL if available (blogs, Substack, podcasts) |
| `youtube_channel_id` | For YouTube monitoring |
| `x_handle` | For Grok/X monitoring |
| `trust_level` | High / Medium / Watch (for weighting in synthesis) |
| `domain_tags` | e.g. `["AI", "finance", "architecture"]` |
| `last_checked` | Timestamp |
| `active` | Boolean toggle |

**Monitoring Tools by Platform:**

- **YouTube channels** → YouTube Data API v3 + Apify transcript[^41][^37]
- **Blogs / Substack / newsletters** → n8n RSS Feed node (built-in)[^42][^43][^44]
- **X/Twitter accounts** → Grok 4 API with DeepSearch (real-time firehose)[^13]
- **LinkedIn** → Apify LinkedIn scraper (triggered on schedule)[^31]
- **Reddit users/subreddits** → ScrapeCreators or Apify Reddit actor[^34]

**Process:** Schedule (every 6 hours) → read active creators from Registry → route by platform → fetch new content since last_checked → AI summarize → relevance-score against active research topics → if score ≥ 7, inject into active research context → update last_checked → push high-relevance items to Knowledge Base with `creator_trusted = true` flag.

The RSS-based content monitoring workflow demonstrated with n8n processes subscribed feeds every hour, uses an LLM to acquire and organize article content, and pushes to messaging platforms (Telegram/Slack) for real-time alerts.[^45]

***

## Part 4: Verification, Validation & Quality Gates

This is the most critical differentiator between a toy pipeline and production-grade research. The system implements four independent verification layers.

### Gate 1 — Source Credibility Scoring

Every retrieved source is scored before content extraction. A three-agent pipeline (Content Analyzer → Scientific/Source Verifier → Credibility Assessor) was validated in a published multi-agent AI pipeline study that demonstrated "substantial agreement with expert assessments" while providing "dramatic speed improvements".[^46]

**Credibility dimensions:**
- Domain authority and publication reputation
- Author credentials and citation count
- Publication recency
- Cross-source corroboration count
- Trusted Creator flag (sources from your Creator Registry get a trust bonus)

**Output:** Credibility score 0–100 per source; sources below threshold (e.g., < 40) are excluded from synthesis but retained in audit log.

### Gate 2 — Hallucination Validation Pipeline

Every claim in synthesized content passes through a **Hallucination Validation Pipeline (HVP)**:[^47][^48][^49]

1. **RAG Layer** — every response grounded in retrieved documents with explicit citations; claims without citation are flagged
2. **Source Validation Engine** — compares generated claims against structured source data; flags inconsistencies[^47]
3. **Factuality & Consistency Scoring** — secondary model (different model family from generator to reduce correlated failures) scores factual alignment; outputs hallucination score[^50]
4. **Retrieval-Augmented Verification** — each generated claim evaluated against search index; unsupported claims are rejected, revised, or regenerated with grounding[^49]

The use of a different model family for validation (e.g., GPT-5 generates, Claude validates) is a deliberate architectural diversity choice to reduce correlated failure modes.[^50]

### Gate 3 — The Devil's Advocate (Red Team Agent)

This is the adversarial challenge run that Nico specifically requested — an agent whose sole job is to **refute, challenge, and stress-test** the synthesized findings.

**Model:** Claude 4.5 Opus (strongest adversarial reasoning)

**System Prompt Pattern:**
> "You are a rigorous Devil's Advocate. You will receive a research synthesis and its sources. Your job is to: (1) identify logical fallacies, (2) find contradicting evidence not in the synthesis, (3) challenge the weakest factual claims, (4) propose alternative interpretations. For each challenge, rate your confidence 0–1 and cite a source. Output as structured JSON."

**Process:** Synthesis → Red Team Agent runs independent Tavily/Firecrawl search for contrary evidence → generates structured rebuttal with confidence scores → rebuttal returned to Synthesizer → Synthesizer produces revised synthesis addressing valid challenges → claims that survive adversarial challenge are marked `verified = true`.[^51][^52][^53]

Research on automated red-teaming demonstrates that even the safest agents still have non-zero failure rates when exposed to unreliable sources (Claude-Sonnet-4.5 with tool-calling: 4.6% ASR), making independent adversarial testing essential rather than optional.[^52]

### Gate 4 — LLM-as-a-Judge Final Quality Gate

A final judge agent evaluates the complete research package before it is written to the Knowledge Base.[^2]

**Evaluation dimensions (score 0.0–1.0 per dimension):**

| Dimension | Threshold |
|-----------|-----------|
| Completeness — all sub-questions answered | ≥ 0.80 |
| Source quality — credibility-weighted average | ≥ 0.70 |
| Factual consistency — no unresolved contradictions | ≥ 0.85 |
| Adversarial survival — red team challenges addressed | ≥ 0.75 |
| Citation density — every claim cited | ≥ 0.90 |

If any dimension falls below threshold, the orchestrator triggers a **Replan** loop — generating new sub-questions targeting the gap — up to a maximum of 3 iterations. This was validated in the VMAO framework where verification-driven replanning produced the largest quality gains.[^5][^4]

Human-in-the-Loop (HITL) gates are triggered for high-stakes outputs (finance reports, legal analysis) where human review is mandatory before knowledge base commit.[^1][^47]

***

## Part 5: The Complete n8n Workflow Architecture

### Master Workflow Structure

```
[Trigger: Webhook / Schedule / Chat]
        │
        ▼
┌─────────────────────────┐
│  ORCHESTRATOR AGENT      │  ← GPT-5.1 (Planner)
│  Query decomposition     │
│  DAG sub-task planning   │
│  Agent role assignment   │
└────────────┬────────────┘
             │ Execute Sub-Workflows (parallel)
    ┌────────┼────────┬────────────┬─────────────┐
    ▼        ▼        ▼            ▼             ▼
[Web      [Academic [Social     [YouTube    [Creator
 Agent]    Agent]    Agent]      Agent]      Monitor]
GPT-4o-   Gemini    Grok 4 +   Gemini +    Schedule
mini +    2.5 Pro   GPT-4o-    Apify       (always-on)
Firecrawl Semantic  mini       YouTube
Tavily    Scholar   Apify      API v3
SerpAPI   ArXiv     ScrapeCreators
             │
             ▼ Tier 1 results → Orchestrator
┌─────────────────────────┐
│  SYNTHESIZER AGENT       │  ← Claude 4.5
│  Cross-source merging    │
│  Initial report draft    │
└────────────┬────────────┘
             ▼
┌─────────────────────────┐
│  VERIFICATION PIPELINE   │
│  Gate 1: Source scoring  │
│  Gate 2: HVP             │
│  Gate 3: Red Team        │  ← Claude 4.5 (adversarial)
│  Gate 4: Judge           │
└────────────┬────────────┘
             │ Pass / Fail
    ┌────────┴──────────┐
    ▼                   ▼
[REPLAN loop]    [APPROVED → Knowledge Base Export]
(max 3 iter)     ↓
                 Notion / Qdrant vector store
                 Only verified sources committed
```

### Sub-Workflow Modular Design

Each agent runs as an **independent n8n sub-workflow** called via the Execute Sub-workflow node. This is the key production pattern: each sub-workflow has a defined input schema, defined output schema, can be independently tested, independently debugged, and updated without touching the orchestrator. The production best-practice rule: if a workflow exceeds 15–20 nodes or has more than 3 branching paths, refactor to sub-workflows.[^54][^6][^8]

**Key sub-workflows:**
- `research-web-agent` — Tavily + Firecrawl + SerpAPI
- `research-academic-agent` — Semantic Scholar + ArXiv + CrossRef
- `research-social-agent` — Apify + ScrapeCreators + Grok
- `research-youtube-agent` — YouTube API + Apify transcripts
- `creator-monitor` (always-on) — RSS + YouTube API + Grok
- `hallucination-validator` — source check + consistency scoring
- `red-team-agent` — adversarial challenge
- `llm-judge` — final quality gate
- `knowledge-base-exporter` — Notion + Qdrant writer

***

## Part 6: Domain-Specific Research Modes

The orchestrator routes to different agent configurations depending on the research topic. The prompt includes domain classification logic that detects query type before dispatching.

### Finance Research Mode

**Agents activated:** Web Agent (Tavily + financial domains), Academic Agent (SSRN, economics papers), Social Agent (X sentiment via Grok, Reddit r/investing), YouTube Agent (financial YouTubers)

**Special tools:** Perplexity Sonar API for live financial data synthesis; SerpAPI with domain filter `site:sec.gov OR site:ft.com OR site:bloomberg.com`[^21]

**Privacy note:** For sensitive financial data, prefer local open-source models (Llama 4, Mistral) to avoid cloud data exposure. Cloud models offer superior fluency but raise data privacy concerns in financial contexts.[^55]

**Trusted Creator examples (pre-populate in Registry):** Financial YouTube channels, Substack finance newsletters, specific X accounts.

### Software Architecture Research Mode

**Agents activated:** Web Agent (Firecrawl for docs, GitHub), Academic Agent (ArXiv cs.SE, ACM Digital Library), Social Agent (Reddit r/softwarearchitecture, Dev.to), YouTube Agent (tech conference talks)

**Special tools:** Exa semantic search for discovering related technical content; Firecrawl for full documentation extraction[^22][^21]

**Trusted Creator examples:** Tech conference YouTube channels (GOTO, InfoQ), architecture newsletter authors, principal engineers on X.

### Vacation Planning Research Mode

**Agents activated:** Web Agent (travel sites, reviews), Social Agent (Reddit r/travel, TikTok travel creators), YouTube Agent (travel vloggers from creator list)

**Special tools:** Tavily with `topic: general` and time range filter for current conditions; Apify for TripAdvisor/Booking review scraping[^19]

**Multi-agent travel planning systems** like VacayMate demonstrated that 5 specialized agents (flights, accommodation, activities, budget, itinerary) with real-time data significantly outperform single-agent approaches.[^56]

***

## Part 7: The Knowledge Base & Source Registry

### Architecture

Only sources that survive the full verification pipeline (Gates 1–4) are committed to the knowledge base. Every source carries a structured metadata record:

```json
{
  "source_id": "uuid",
  "url": "https://...",
  "title": "...",
  "domain": "finance | tech | travel | academic",
  "source_type": "web | academic | social | youtube | creator",
  "creator_trusted": true,
  "creator_name": "...",
  "credibility_score": 87,
  "hallucination_checked": true,
  "adversarial_survived": true,
  "judge_score": 0.91,
  "run_id": "research-run-2026-04-06",
  "research_query": "...",
  "extracted_at": "ISO timestamp",
  "citation": "APA formatted"
}
```

### Notion Knowledge Base Integration

The n8n Notion Knowledge Base AI Assistant (official template) uses an AI Agent with RAG to query the Notion database, provides reference links to exact pages used, and offers full conversational access to the knowledge store. The setup:[^57][^58]

1. n8n writes verified source records to a Notion database via the Notion node
2. A separate n8n RAG agent uses the Notion node + OpenAI embeddings to answer queries
3. Every response includes the Notion page link for direct verification[^57]

### Vector Store (Qdrant — Self-Hosted)

For semantic search across all accumulated research, Qdrant is the recommended self-hosted vector store (aligns with your self-hosted n8n setup). The n8n Qdrant Vector Store node supports Insert, Get, Retrieve (as Tool for AI Agent), and Retrieve (as Vector Store for Chain).[^59][^60]

**Pipeline:** Verified source → chunk text → OpenAI `text-embedding-3-small` embeddings → upsert to Qdrant collection → n8n AI Agent with Qdrant as tool for semantic retrieval.[^61][^60]

For NotebookLM integration, the Apify NotebookLM API actor exports notebooks in JSON/CSV/Markdown with source URLs, citation mappings, and AI-generated summaries — ready to feed directly into RAG pipelines or n8n workflows.[^62]

### The Source Registry for Notebook Knowledge Base

At the end of every research run, a final workflow exports:
1. **Verified sources list** (only sources that passed all gates) → Notion source database
2. **Rejected sources log** (with reason: credibility fail / hallucination fail / red-team refuted) → separate audit table
3. **Research run manifest** (query, run_id, timestamp, agent configs, model versions) → run log
4. **Vector embeddings** of all verified content → Qdrant for semantic retrieval

This means only the sources that are "really valid" (as you specified) are committed to the notebook — the rejected sources never enter the knowledge base but are traceable in the audit log.

***

## Part 8: n8n Production Configuration

### Infrastructure

- **Deployment:** Self-hosted n8n on Docker (aligns with your existing setup)[^1]
- **Queue mode** for parallel agent execution — critical for running 5 agents simultaneously[^1]
- **Workers:** minimum 3–5 worker processes for parallel sub-workflow execution

### AI Agent Guardrails (Production Checklist)[^6]

- [ ] AI output validated before any downstream action triggers
- [ ] Each agent has only the tools needed for its specific task (principle of least privilege)
- [ ] Human-in-the-loop gates for high-stakes outputs (finance, medical)
- [ ] Kill switch per agent workflow — pausable without infrastructure changes
- [ ] Prompts versioned separately from workflow logic
- [ ] Model versions pinned — silent model updates must not change behavior
- [ ] Max 15–20 nodes per workflow; overflow goes to sub-workflows

### Error Handling Pattern

Every sub-workflow wraps agent calls in error handling nodes. If a Research Agent sub-workflow fails, the orchestrator catches the error, logs it, and either retries (up to 3×) or marks that data tier as partial — synthesis proceeds with available data rather than halting entirely.[^63][^1]

### Cost Optimization

- Route classification and deduplication to GPT-4o-mini
- Use Gemini 2.5 Pro for high-volume document processing (cheapest frontier model at $1.25/$5 per M tokens)[^11]
- Enable OpenAI cached inputs for repeated orchestrator context (90% discount)[^9]
- Use Qdrant self-hosted to avoid ongoing vector DB fees

***

## Part 9: Trusted Content Creator Registry — Implementation

### Initial Population

Populate the Creator Registry with a Google Sheets or Notion database containing creators across these categories (add/remove as needed):

| Category | Platform | Examples to Consider |
|----------|----------|---------------------|
| AI/ML Research | YouTube + X | AI lab channels, ML conference recordings |
| Finance | YouTube + Substack + X | Financial analysts, macro economists |
| Software Architecture | YouTube + Blog | Principal engineers, CTO blogs, GOTO/InfoQ |
| Venture & Startup | X + Substack | VC firms, founder newsletters |
| News & Journalism | RSS + X | Tech publications with RSS feeds |
| Domain Experts | Platform varies | Per-topic specialists you personally vet |

### Creator Discovery Sub-Agent

An optional **Creator Discovery Agent** can auto-discover new trusted creators by:
1. Monitoring which sources appear repeatedly in high-scoring research runs
2. Using YouTube API to identify channels posting in topic areas with high engagement[^64]
3. Presenting candidates to the human (HITL gate) for approval before adding to Registry

New creators enter with `trust_level: Watch` and are upgraded to `trust_level: High` only after their content has been validated in multiple research runs.

***

## Part 10: Full Source Quality Lifecycle

```
┌──────────────────────────────────────────────────────────┐
│                   RESEARCH RUN LIFECYCLE                   │
│                                                            │
│  1. Query ingestion + domain classification                │
│  2. Orchestrator DAG planning                              │
│  3. Parallel Tier-1 agent execution (web/academic/social/ │
│     YouTube/creator monitor)                               │
│  4. Source credibility scoring (Gate 1)                    │
│     → Sources < threshold → REJECTED (audit log)          │
│  5. Cross-source synthesis (Claude 4.5)                    │
│  6. Hallucination validation (Gate 2)                      │
│     → Failed claims flagged → regenerated with grounding  │
│  7. Devil's Advocate / Red Team challenge (Gate 3)         │
│     → Refuted claims removed or challenged in report      │
│  8. LLM-as-Judge final score (Gate 4)                      │
│     → Score < threshold → REPLAN (max 3 iterations)       │
│  9. HITL review for high-stakes domains                    │
│  10. Approved → write to Knowledge Base                    │
│      ✓ Notion source database (verified sources only)     │
│      ✓ Qdrant vector store (semantic search)               │
│      ✓ Research run manifest (full audit trail)            │
│      ✗ Rejected sources → audit log (never in notebook)   │
└──────────────────────────────────────────────────────────┘
```

***

## Part 11: Reference Tools & APIs Summary

### n8n Nodes Required

| Node | Purpose |
|------|---------|
| AI Agent | Core agent logic, tool orchestration |
| Execute Sub-workflow | Modular agent calls |
| OpenAI Chat Model | GPT-5.1, GPT-4o-mini |
| xAI Grok Chat Model | Grok 4 with DeepSearch |
| Google Gemini Chat Model | Gemini 3 / 2.5 Pro |
| Anthropic Claude | Claude 4.5 Opus |
| HTTP Request | Semantic Scholar, ArXiv, OpenAlex, Grok API, YouTube API, ScrapeCreators |
| Apify | Social scraping, YouTube transcripts, NotebookLM export |
| Tavily | Real-time web search |
| RSS Feed | Creator blog/Substack monitoring |
| YouTube (built-in) | Channel data, video metadata |
| Qdrant Vector Store | Self-hosted semantic vector DB |
| Notion | Knowledge base write/read |
| Google Sheets | Creator Registry, dedup log, results |
| Schedule Trigger | Creator monitor (every 6h) |
| Webhook | On-demand research trigger |
| Evaluations Trigger | n8n Evals quality testing |
| Wait | Rate limiting |
| If / Switch | Quality gate routing |
| Loop Over Items | Batch processing |

### External APIs & Services

| Service | Use | Pricing Model |
|---------|-----|---------------|
| OpenAI API | GPT-5.1, GPT-4o-mini, embeddings | Per token |
| Anthropic API | Claude 4.5 Opus | Per token |
| Google AI | Gemini 3 / 2.5 Pro | Per token |
| xAI API (x.ai/api) | Grok 4 + DeepSearch | Per token |
| Tavily | Web search | Per request |
| Firecrawl | Full-page scraping | Credits |
| Exa | Semantic search | Credits |
| SerpAPI | SERP results | Per request |
| Apify | Social scraping, YouTube | Compute units |
| ScrapeCreators | Multi-platform social | Per request |
| Semantic Scholar | Academic papers | Free API |
| ArXiv | Preprint papers | Free API |
| OpenAlex | Open scholarly works | Free API |
| Perplexity Sonar | Deep research API | Per request |
| Qdrant | Vector DB | Self-hosted free |
| Pinecone | Vector DB (cloud alt.) | Free tier + usage |
| Notion API | Knowledge base | Free/Pro plan |
| YouTube Data API v3 | Channel/video data | Free quota |

***

## Conclusion

The ideal research workflow is not a single monolithic pipeline — it is a **coordinated system of specialized agents** operating in parallel, checked by independent validators, challenged by adversarial red-teaming, and filtered by strict quality gates before any source earns a place in the knowledge base. Built on n8n's modular sub-workflow architecture, this system scales from a single vacation-planning query to continuous multi-domain research intelligence.

The four-model stack (GPT-5.1 + Claude 4.5 + Gemini 3 + Grok 4) is not redundant — each model covers a distinct strength: planning, accuracy, scale, and real-time social grounding respectively. The Trusted Content Creator Registry transforms passive scraping into active intelligence from vetted human experts, whose outputs receive elevated trust weighting throughout the verification pipeline.

Sources that survive all four quality gates — credibility scoring, hallucination validation, adversarial challenge, and LLM judgment — become permanent, citable assets in a semantic knowledge base. Everything else is logged but never promoted, preserving knowledge base integrity across every research run.

---

## References

1. [15 best n8n practices for deploying AI agents in production](https://blog.n8n.io/best-practices-for-deploying-ai-agents-in-production/) - This guide covers the 15 best n8n practices for deploying AI agents that run reliably in production....

2. [How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)

3. [[PDF] Verified Multi-Agent Orchestration: A Plan-Execute-Verify-Replan ...](https://arxiv.org/pdf/2603.11445.pdf)

4. [Verified Multi-Agent Orchestration: A Plan-Execute-Verify-Replan ...](https://arxiv.org/html/2603.11445v1)

5. [Verified Multi-Agent Orchestration: A Plan-Execute-Verify-Replan Framework for Complex Query Resolution](https://arxiv.org/pdf/2603.11445v1.pdf)

6. [n8n Best Practices Checklist for Production (2026)](https://hatchworks.com/blog/ai-agents/n8n-best-practices/) - The 2026 n8n best practices checklist: six categories of production-ready standards for security, er...

7. [LLMs and Multi-Agent Systems: The Future of AI in 2025](https://www.classicinformatics.com/blog/how-llms-and-multi-agent-systems-work-together-2025) - Explore how LLMs and Multi-Agent Systems work together to tackle complex tasks and revolutionize AI ...

8. [Build a Multi-Agent Workflow in n8n (Orchestrator + Agents ...](https://www.innovatrixinfotech.com/blog/build-multi-agent-workflow-n8n) - Step-by-step: build a 3-agent n8n pipeline with orchestrator, research agent, and writer agent. Real...

9. [Best Agentic LLM Models & Frameworks 2026 - Adaline](https://www.adaline.ai/blog/top-agentic-llm-models-frameworks-for-2026) - A data-driven comparison of GPT-5.2, Gemini 3, and Claude 4.5—plus the framework battle determining ...

10. [Top 5 LLM Models in 2025: Gemini 3, Claude 4.5, GPT-5.1, Grok 4 ...](https://vertu.com/ai-tools/top-5-llm-models-in-2025-leading-ai-systems-shaping-the-future/) - Find the Top 5 LLM Models in 2025 including Gemini 3 (Multimodal), Claude 4.5 Opus (Enterprise/Accur...

11. [Claude vs GPT-4 vs Gemini: Which LLM for Production AI Agents?](https://getathenic.com/blog/anthropic-claude-vs-openai-gpt4-vs-google-gemini) - Comprehensive comparison of Claude 3.5 Sonnet, GPT-4o, and Gemini 1.5 Pro for building production AI...

12. [ChatGPT 5.1 vs Claude vs Gemini: A Balanced Comparison (2025)](https://skywork.ai/blog/ai-agent/chatgpt-5-1-vs-claude-vs-gemini-2025-comparison/) - ChatGPT 5.1 vs Claude vs Gemini: Compare 2025's latest AI models by reasoning modes, multimodality, ...

13. [HOW THE XAI GROK 4.20 AGENTS WORK | NextBigFuture.com](https://www.nextbigfuture.com/2026/02/how-the-xai-grok-4-20-agents-work.html) - – Official developer guides (2025) detail “manager pattern” (central LLM calls specialist agents as ...

14. [how to use grok ai for advanced research workflows 2026 - YouTube](https://www.youtube.com/watch?v=l46Y9PJD6DY) - In this video, you'll learn how to use Grok AI for advanced research workflows in 2026 step by step....

15. [Grok AI Assistant: The Complete 2026 Guide to xAI's Real-Time Model](https://skywork.ai/skypage/en/grok-ai-real-time-model-guide/2032304113992433664) - Explore xAI's Grok AI: real‑time X integration, multimodal tools, low‑cost API, and enterprise workf...

16. [Build AI Agent in n8n using xAI Grok!](https://www.youtube.com/watch?v=_F1CVi19n7I) - In this video I cover how you can easily plug in xAI's Grok API into your n8n workflow with their AI...

17. [xAI Grok Chat Model integrations | Workflow automation with n8n](https://n8n.io/integrations/xai-grok-chat-model/) - Integrate xAI Grok Chat Model with hundreds of other apps. Create sophisticated automations between ...

18. [How to Add Grok 4 to n8n AI Agents (+Vision and Real-Time Search)](https://www.youtube.com/watch?v=zo26u39LIbE) - 🚀 Access ALL video resources & get personalized help in my community:
https://www.skool.com/agentic-...

19. [Tavily + n8n — Real-time web data, low code](https://www.tavily.com/blog/building-autonomous-workflows-tavily-n8n-real-time-web-data-low-code) - This guide shows how combining Tavily's real-time search and extraction with n8n's low-code workflow...

20. [n8n - Tavily Docs](https://docs.tavily.com/documentation/integrations/n8n) - Tavily is now available for no-code integration through n8n.

21. [5 Best Deep Research APIs for Agentic Workflows in 2026 - Firecrawl](https://www.firecrawl.dev/blog/best-deep-research-apis) - Compare the top deep research APIs for building AI agents and agentic workflows. From autonomous web...

22. [Best AI Search Engines for Agents and Workflows in 2026 - Firecrawl](https://www.firecrawl.dev/blog/best-ai-search-engines-agents) - Not all AI search engines are built for agents. Here's a developer breakdown of the top options — Fi...

23. [Efficient SERP Analysis & Export Results to Google Sheets (SerpApi ...](https://www.reddit.com/r/n8n/comments/1kc5kin/efficient_serp_analysis_export_results_to_google/) - A set of free n8n templates for automating SERP analysis. I built these mainly to speed up keyword r...

24. [Build a Real-Time AI Agent with n8n & SERPAPI (No Code)](https://www.youtube.com/watch?v=aiEcHXAme0M) - **🔎 Build a Real-Time AI Search Agent with N8N & SERPAPI! 🚀**  

🔗 Join here: https://www.skool.com/...

25. [Top 10 Deep Research Agents in 2025 (Alici, Kimi, Gemini, Claude)](https://alici.ai/blog/top-deep-research-agents-2025) - In-depth 2025 comparison of Alici.ai Research Playbooks, Kimi-Researcher, OpenAI DeepResearch, Gemin...

26. [The Semantic Scholar Open Data Platform - arXiv](https://arxiv.org/html/2301.10140v2)

27. [Semantic Scholar Integration for AI Agents - Tars Chatbots](https://hellotars.com/tools/semanticscholar) - Connect Semantic Scholar to Tars AI Agents. Search papers, retrieve citations, and explore author pr...

28. [Scientific agents are getting a lot more real. AutoResearchClaw is ...](https://www.instagram.com/reel/DWZiXCpAcY9/) - rediminds on March 27, 2026: "Scientific agents are getting a lot more real. AutoResearchClaw is an ...

29. [AutoResearchClaw: Autonomous Multi-Agent System for End ...](https://agent-wars.com/news/2026-03-15-autoresearchclaw-paper-generation) - AutoResearchClaw is one of the most technically complete entries yet in the growing class of tools t...

30. [AutoResearchClaw: We Ran a Fully Autonomous Research Pipeline](https://themenonlab.blog/blog/autoresearchclaw-autonomous-research-pipeline) - Real results from running AutoResearchClaw's 23-stage autonomous research pipeline. Setup guide, art...

31. [How to Build a Social Media Scraper AI Agent with n8n](https://www.youtube.com/watch?v=QtNRH6mHWlA) - ♥️ *Get N8n Hosting & Workflow* ➜ https://webspacekit.com/client/link.php?id=182

❤️ *LIMITED TODAY:...

32. [I Built an AI Agent That Scrapes Social Media in Seconds (n8n + Apify Tutorial)](https://www.youtube.com/watch?v=Gj_ZKlcsXR8) - Full systems + unlimited support: https://go.mikefutia.com/scale-youtube

Work with me: https://go.m...

33. [7 Essential AI Agents Tools You Should Use in n8n! (2025) - YouTube](https://www.youtube.com/watch?v=i0FfNB4E6pM) - ... Firecrawl 05:01 API-Template.io 07:35 Apify 09:45 Mistral 11:46 Tavily 13:10 Pinecone If You're ...

34. [Scrape EVERY Social Media with n8n (CHEAP & EASY)](https://www.youtube.com/watch?v=PY1id4-m6NI&vl=en) - Check out scrapecreators here: https://scrapecreators.com/?via=scrapes

🚀 All my paid resources inc....

35. [Scrape EVERY Social Media with n8n (CHEAP & EASY)](https://www.youtube.com/watch?v=PY1id4-m6NI) - Check out scrapecreators here: https://scrapecreators.com/?via=scrapes

🚀 All my paid resources inc....

36. [Fully Automated Social Media Agent with n8n & Google Trends (No Code!) | Step by Step Tutorial](https://www.youtube.com/watch?v=3CQQwHh2K58) - Join Me on Telegram for getting useful resources-  https://t.me/+IZsBvr-jANc2Yzk1

Tired of manual c...

37. [YouTube channel monitor with Video Stats, AI transcription ... - N8N](https://n8n.io/workflows/9268-youtube-channel-monitor-with-video-stats-ai-transcription-and-summarization/) - This n8n workflow automatically monitors YouTube channels, transcribes new videos, and generates AI-...

38. [How to Scrape ANY YouTube Video Transcript with n8n! (full workflow)](https://my.infocaptor.com/hub/summaries/ai-foundations/how-to-scrape-any-youtube-video-transcript-with-n8n-full-workflow-pAOOfeKYaSQ) - The video demonstrates a three-part workflow for extracting YouTube transcripts and storing them in ...

39. [How to Scrape ANY YouTube Video Transcript with n8n! (full workflow)](https://www.youtube.com/watch?v=pAOOfeKYaSQ) - Master AI through courses and community: https://www.skool.com/ai-foundations Master AI agents in n8...

40. [Transcribe Video and Make Timestamps Using N8N - YouTube](https://www.youtube.com/watch?v=C3oakGaQfzE) - Learn how to auto transcribe videos and make timestamps using n8n, Open AI, and Apify.com. This work...

41. [Monitor multiple YouTube channels with real-time RocketChat alerts](https://n8n.io/workflows/10643-monitor-multiple-youtube-channels-with-real-time-rocketchat-alerts/) - This n8n workflow provides automated monitoring of YouTube channels and sends real-time notification...

42. [Automated blog content tracking with RSS feeds and time-based ...](https://n8n.io/workflows/9596-automated-blog-content-tracking-with-rss-feeds-and-time-based-filtering/) - This workflow provides a powerful yet simple foundation for monitoring blogs using RSS feeds. It aut...

43. [Auto Tech Newsletter from RSS: Free n8n AI Agent Workflow](https://hackceleration.com/automations-to-download/ai-agent-n8n-auto-tech-newsletter-rss/) - Download this free n8n AI agent that generates your daily tech newsletter automatically. Claude Sonn...

44. [Automated RSS feed workflow with n8n & Outlook - Kutzschbach](https://www.kutzschbach.de/en/rss-feed-workflow/) - A workflow was developed for this purpose: Automatic retrieval of RSS feeds from important websites ...

45. [Building Your Own RSS Feed Subscription Management & AI Large ...](https://dev.to/yeshan333/building-your-own-rss-feed-subscription-management-ai-large-model-reading-workflow-with-n8n-2lia) - Recently, I used n8n to orchestrate a workflow to replace my previous backend application rss_generi...

46. [Development and validation of a multi-agent AI pipeline for ... - PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12757325/) - To validate the automated framework's credibility scores, two expert reviewers independently evaluat...

47. [How to Build a Hallucination Validation Pipeline for AI-Generated ...](https://www.linkedin.com/posts/rakesh-khanduja-61567913_how-to-build-a-hallucination-validation-pipeline-activity-7382644585392529408-SkyN) - How to Build a Hallucination Validation Pipeline for AI-Generated Content In the age of GenAI, conte...

48. [How to Test AI Reliability: Detect Hallucinations and Build End-to ...](https://www.getmaxim.ai/articles/how-to-test-ai-reliability-detect-hallucinations-and-build-end-to-end-trustworthy-ai-systems/) - AI reliability requires systematic hallucination detection and continuous monitoring across the enti...

49. [AI Hallucination Detection Tools: W&B Weave & Comet - AIMultiple](https://aimultiple.com/ai-hallucination-detection) - We benchmarked 3 AI hallucination detection tools across 100 test cases using identical datasets and...

50. [A Framework for Assessing AI Agent Decisions and Outcomes in ...](https://arxiv.org/html/2602.22442v2) - Modern agent-based AutoML systems model machine learning pipelines as sequences of interconnected de...

51. [Learning-Based Automated Adversarial Red-Teaming for ... - arXiv](https://arxiv.org/html/2512.20677v3)

52. [SafeSearch: Automated Red-Teaming of LLM-Based Search Agents](https://arxiv.org/html/2509.23694v4) - In response to the research question, our study highlights the overall high vulnerability of LLM-bas...

53. [[PDF] Red Teaming AI Systems for Security Validation](https://ijaibdcms.org/index.php/ijaibdcms/article/download/248/251) - A timeline of the evolution in AI threat views: adversarial examples (2017), data poisoning (2019), ...

54. [Multi-agent system: Frameworks & step-by-step tutorial - n8n Blog](https://blog.n8n.io/multi-agent-systems/) - Discover multi-agent AI patterns, communication, costs, risks, and real-world use cases. Compare vis...

55. [Comparing Open-Source and Commercial LLMs for Domain-Specific Analysis and Reporting: Software Engineering Challenges and Design Trade-offs](https://arxiv.org/abs/2509.24344) - Context: Large Language Models (LLMs) enable automation of complex natural language processing acros...

56. [VacayMate: When AI Agents Become Your Personal Travel Bureau](https://app.readytensor.ai/publications/vacaymate-when-ai-agents-become-your-personal-travel-bureau-RIAGyo2bgTBG)

57. [Notion knowledge base AI assistant | n8n workflow template](https://n8n.io/workflows/2413-notion-knowledge-base-ai-assistant/) - Who is this forThis workflow is perfect for teams and individuals who manage extensive data in Notio...

58. [How to Set Up a Notion Knowledge Base AI Assistant](https://www.youtube.com/watch?v=ynLZwS2Nhnc) - This video walks through set up of the Notion Knowledge Base AI Assistant (a project made by Max Tka...

59. [Qdrant Vector Store node documentation - n8n Docs](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.vectorstoreqdrant/) - Learn how to use the Qdrant Vector Store node in n8n. Follow technical documentation to integrate Qd...

60. [N8N and Qdrant Vector Store: A Tutorial on RAG](https://www.convert.com/blog/ai/n8n-qdrant-vector-store-rag-tutorial/) - A guide to implementing Retrieval-Augmented Generation in n8n using Qdrant vector storage and Ollama...

61. [Pinecone Vector Store node documentation](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.vectorstorepinecone/) - Learn how to use the Pinecone Vector Store node in n8n. Follow technical documentation to integrate ...

62. [NotebookLM API - Export Notebooks, Sources & Citations - Apify](https://apify.com/clearpath/notebooklm-api) - Output to JSON, CSV, Markdown or Excel. Bulk export or select specific notebooks. Perfect for n8n wo...

63. [[PDF] Verification-Aware Planning for Multi-Agent Systems - ACL Anthology](https://aclanthology.org/2026.eacl-long.353.pdf)

64. [[Paid] Need an n8n Agent to find YouTube creators by keywords ...](https://www.reddit.com/r/n8n/comments/1mq9rw8/paid_need_an_n8n_agent_to_find_youtube_creators/) - I'm looking to hire someone to build an n8n workflow (or set of workflows) that finds relevant YouTu...

