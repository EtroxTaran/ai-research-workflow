# n8n Workflow-Spezifikationen

> **⚠️ DEPRECATED — Diese Sub-Workflow-Architektur wurde nie deployed.**
> Die tatsächliche Implementierung ist ein Monolith: `workflows/research-orchestrator-monolith.json` (53 Nodes, Sprint 1+2 vollständig).
> Diese Datei bleibt als Design-Referenz erhalten. Für den aktuellen Stand: `docs/research-modes.md` und `docs/agent-integration.md`.

---

> Technische Specs für alle Sub-Workflows des Research Systems.
> Zielplattform: B-Link R2D2 (lokal, 24/7) — CLI-first Architektur
> Version: 2.0 (Adaptive Pipeline, CLI-first, kein Perplexity)

---

## Übersicht: Sub-Workflow-Hierarchie

```
research-orchestrator (Main Workflow)
  │
  ├─[1] research-phase0-plan
  │
  ├─[2] research-phase1-gather (Parallel-Dispatch)
  │     ├── research-search-kb
  │     ├── research-search-web
  │     ├─��� research-search-deep (Gemini CLI + Search Grounding)
  │     ├── research-search-social (Grok 4 API)
  │     ├── research-search-academic
  │     ├── research-search-youcom (You.com API, optional Deep)
  │     └── research-search-miniflux
  │
  ├─[3] research-phase2-counter
  │
  ├─[4] research-phase3-verify
  │     ├── research-verify-cove
  │     ├── research-verify-factscore
  │     └── research-judge
  │
  ├─[5] research-phase4-synthesize
  │
  ├─[6] research-deliver
  │
  └─[7] research-hitl
```

---

## 1. research-orchestrator (Main Workflow)

### Trigger

| Trigger-Node | Input | Beschreibung |
|---|---|---|
| Webhook (POST `/webhook/research-start`) | `{run_id, query, domain, language, mode, config}` | Portal / OpenClaw / API |
| Schedule Trigger | Pre-konfigurierte Queries | Weekly Digest, Continuous Monitor |
| Manual Trigger | n8n UI Input | Testing |
| Telegram Bot | Natural Language Query | Direkte User-Anfrage |

### Flow

```
Trigger
  │
  ├── SET: run_id generieren (falls nicht vorhanden)
  ├── HTTP Request: SurrealDB — CREATE research_run (status: pending)
  │
  ├── Execute Sub-Workflow: research-phase0-plan
  │     └── Output: search_plan JSON + mode (quick|standard|deep)
  │
  ├── HTTP Request: SurrealDB — UPDATE research_run (status: phase1, search_plan: $plan, mode: $mode)
  │
  ├── Execute Sub-Workflow: research-phase1-gather
  │     └── Output: sources[], claims[]
  │
  ├── IF mode == "standard" OR "deep":
  │     ├── IF: Gate 1 (Standard: ≥8 sources ≥2 platforms, Deep: ≥12 ≥3 ≥5 T1/T2)
  │     │     ├── PASS → Continue
  │     │     └── FAIL → Replan oder HITL
  │     │
  │     ├── IF mode == "deep":
  │     │     ├── Execute Sub-Workflow: research-phase2-counter
  │     │     │     └── Output: counter_evidence[], contradictions[]
  │     │     └── IF: Gate 2 (≥80% claims have counter-research)
  │     │
  │     ├── Execute Sub-Workflow: research-phase3-verify
  │     │     └── Output: verification_table[]
  │     │
  │     └── IF: Gate 3 (Standard: ≥70% verified, Deep: ≥80% + judge ≥3.5)
  │           ├── PASS → Continue
  │           └── FAIL (retries < 3) → Identify weak phase → Replan
  │           └── FAIL (retries ≥ 3) → HITL Escalation
  │
  ├── Execute Sub-Workflow: research-phase4-synthesize
  │     └── Output: report_markdown
  │
  ├── Quality Gate Check (structural)
  │
  ├── IF: Confidence ≥ threshold (Quick: 60%, Standard: 70%, Deep: 80%)
  │     ├── YES → Execute Sub-Workflow: research-deliver
  │     └── NO → Execute Sub-Workflow: research-hitl
  │
  └── HTTP Request: SurrealDB — UPDATE research_run (status: completed)
```

### Error Handling
- Jeder Execute Sub-Workflow Node hat Error Branch
- Error → Log to SurrealDB + Telegram Notification
- Circuit Breaker: 3 consecutive failures → 15min cooldown

---

## 2. research-phase0-plan

### Input
```json
{
  "query": "string — natürliche Sprache",
  "domain": "string — auto-classified oder override",
  "language": "string — de|en",
  "mode": "string — standard|weekly_digest|product_comparison|..."
}
```

### Nodes
1. **Execute Command** — Codex CLI für Query Analysis + Decomposition + Modus-Klassifizierung
   ```bash
   codex exec "Analysiere diese Forschungsfrage und liefere ein JSON mit:
   1. sub_questions (array)
   2. search_terms (primary_de, primary_en, counter_de, counter_en)
   3. sources (welche Branches relevant sind)
   4. scope (time_range, languages, exclusion_criteria)
   5. domain_classification
   6. mode (quick|standard|deep) basierend auf Komplexität

   Query: {{query}}

   Regeln für Modus:
   - quick: Einfache Fakten, kurze Antworten, eine Perspektive reicht
   - standard: Vergleiche, Analysen, multiple Perspektiven nötig
   - deep: Investitionsentscheidungen, Tech-Evaluierungen, hohe Konsequenz

   Antwort NUR als JSON."
   ```

2. **Code Node** — JSON parsen + Modus-Override prüfen (User kann `[deep]` im Query angeben)
3. **Execute Command** — KB-Check: Haben wir schon etwas zu diesem Thema?
   - `python3 ~/.openclaw/workspace/scripts/kb-search.py "{{query}}"` (minimal, nur Existenz-Check)

### Output
```json
{
  "search_plan": { ... },
  "kb_existing": true|false,
  "kb_hits_count": 0
}
```

---

## 3. research-phase1-gather

### Input
`search_plan` JSON aus Phase 0

### Nodes (PARALLEL via n8n Split-Merge)

```
search_plan
  │
  ├── Branch A: research-search-kb ─────────────────┐
  ├── Branch B: research-search-web ────────────────┤
  ├── Branch C: research-search-deep (Gemini CLI) ──┤
  ├── Branch D: research-search-social (Grok API) ──┤── Merge Node
  ├── Branch E: research-search-academic ───────────┤
  ├── Branch F: research-search-miniflux ───────────┤
  └── Branch G: research-search-youcom (optional) ──┘
        │
        ▼
  Deduplication (Code Node: URL-basiert)
        │
        ▼
  Source Credibility Scoring (Gate 1)
        │
        ▼
  Claim Extraction (AI Agent)
```

### Output
```json
{
  "sources": [
    {
      "url": "string",
      "title": "string",
      "date": "ISO datetime",
      "platform": "web|academic|social|youtube|rss|kb",
      "tier": "T1|T2|T3",
      "relevance_score": 0.85,
      "credibility_score": 72,
      "creator_trusted": false,
      "content_summary": "string (500 chars max)",
      "raw_content": "string (full text)"
    }
  ],
  "claims": [
    {
      "id": "c-1",
      "text": "string",
      "source_urls": ["..."],
      "confidence": 0.7
    }
  ],
  "gate1_passed": true,
  "stats": {
    "total_sources": 15,
    "unique_platforms": 4,
    "t1_t2_sources": 8
  }
}
```

---

## 4. Sub-Workflow: research-search-web

### Nodes
1. **HTTP Request** — Brave Search API
   - `GET https://api.search.brave.com/res/v1/web/search?q={{search_terms}}`
   - Header: `X-Subscription-Token: {{BRAVE_API_KEY}}`

2. **HTTP Request** — Tavily Search (parallel mit Brave)
   - `POST https://api.tavily.com/search`
   - Body: `{"query": "{{search_terms}}", "search_depth": "advanced", "max_results": 10}`

3. **Code Node** — Merge + Deduplicate (URL-basiert)

4. **HTTP Request** — Tavily Extract (Top 5 URLs)
   - `POST https://api.tavily.com/extract`
   - Body: `{"urls": ["..."]}`

### Output
Array von Source-Objekten mit URL, Titel, Content, Datum.

---

## 5. Sub-Workflow: research-search-deep (Gemini CLI + Search Grounding)

Ersetzt Perplexity Sonar — nutzt Gemini CLI mit nativem Google Search Grounding (5K free/Mo).

### Nodes
1. **Execute Command** — Gemini CLI mit Search Grounding
   ```bash
   gemini -p "Recherchiere umfassend mit Web-Quellen zum Thema: {{research_query}}.
   Gib für jede Aussage die Quellen-URL an.
   Format: Strukturierte Analyse mit nummerierten Quellen am Ende.
   Sprache: {{language}}" --sandbox
   ```

2. **Code Node** — Output parsen: Synthese-Text + URLs extrahieren

### Output
Synthesis-Text + Array von zitierten URLs (aus Google Search Grounding).

### Modus
Standard + Deep (nicht für Quick — dort reicht Branch B).

---

## 5b. Sub-Workflow: research-search-youcom (You.com Research API — optional)

Nur im Deep-Modus. #1 auf DeepSearchQA Benchmark. $100 Free Credit.

### Nodes
1. **HTTP Request** — You.com Research API
   ```
   GET https://api.ydc-index.io/research
     ?query={{research_query}}
   Authorization: Bearer {{YOUCOM_API_KEY}}
   ```

2. **Code Node** — Extract answer + citations

### Output
Research-Synthese mit zitierten URLs.

---

## 6. Sub-Workflow: research-search-miniflux

### Nodes
1. **HTTP Request** — MiniFlux Search
   ```
   GET http://localhost:8070/v1/entries
     ?search={{keywords}}
     &status=unread
     &limit=50
     &order=published_at
     &direction=desc
   Authorization: {{MINIFLUX_API_KEY}}
   ```

2. **Code Node** — Filter nach Relevanz + Domain-Matching
3. **Code Node** — Content-Extraktion aus Entry-Feldern

### Output
Array von RSS-Einträgen mit Content, URL, Feed-Name, Datum. Auto-T2 Trust.

---

## 7. Sub-Workflow: research-search-academic

### Nodes
1. **HTTP Request** — Semantic Scholar
   ```
   GET https://api.semanticscholar.org/graph/v1/paper/search
     ?query={{search_terms}}
     &limit=20
     &fields=title,abstract,url,citationCount,year,authors
   ```

2. **HTTP Request** — ArXiv (parallel)
   ```
   GET http://export.arxiv.org/api/query
     ?search_query=all:{{search_terms}}
     &max_results=20
     &sortBy=relevance
   ```

3. **Code Node** — Merge + Dedup (nach DOI/Titel)
4. **Code Node** — Relevanz-Scoring (Citation Count, Recency, Keyword Match)

### Output
Array von Paper-Objekten mit Titel, Abstract, URL, Autoren, Citations, Jahr.

---

## 8. Sub-Workflow: research-search-social

### Nodes
1. **xAI Grok Chat Model** Node (native n8n)
   - Model: Grok 4
   - System: "Search X/Twitter for recent discussions, opinions, and trends about: {{topic}}"
   - `search_parameters: {mode: "auto"}` für DeepSearch

2. **Code Node** — Structured Extraction (Posts, Sentiment, Key Opinions)

### Output
Array von Social-Posts mit Author, Content, Engagement, Sentiment-Score.

---

## 9. YouTube-Integration (via Gemini CLI in Branch C)

YouTube wird nicht als eigener Branch implementiert, sondern über Branch C (Gemini CLI) abgedeckt.
Bei Bedarf kann `yt-transcript.py` in einem Code Node aufgerufen werden:

```bash
python3 ~/.openclaw/workspace/scripts/yt-transcript.py "{{video_url}}"
```

Die Gemini CLI mit Search Grounding findet automatisch YouTube-Inhalte als Teil der Google-Suche.

---

## 10. research-phase2-counter

### Input
Claims aus Phase 1

### Nodes
1. **Loop Over Items** — Für jede Kernaussage (max 15):

   a. **HTTP Request** — Counter-Search (Brave/Tavily mit negated Terms)
      - `"{{claim}} Probleme Kritik scheitert Nachteile"`

   b. **Execute Command** — Claude CLI (Opus) — Devil's Advocate
      ```bash
      claude -p "Du bist ein kritischer Analyst. Generiere die 5 stärksten Gegenargumente zu: {{claim}}" --model opus
      ```

   c. **Execute Command** — Claude CLI (Opus) — Pre-Mortem
      ```bash
      claude -p "Wenn diese Empfehlung in 6 Monaten falsch ist — warum? Claim: {{claim}}" --model opus
      ```

2. **Code Node** — Widersprüche identifizieren (Source A sagt X, Source B sagt Y)

### Output
```json
{
  "counter_evidence": [...],
  "devils_advocate": { "arguments": [...], "pre_mortem": "..." },
  "contradictions": [
    { "sourceA": "...", "claimA": "...", "sourceB": "...", "claimB": "...", "resolution": null }
  ]
}
```

---

## 11. research-phase3-verify

### Nodes (Sub-Workflows, teilweise parallel)

1. **Execute Sub-Workflow: research-verify-cove**
   - Code Node: `python3 research-quality-gate.py --cove --claims '{{claims_json}}'`
   - Factored CoVe: Verifikationsfragen ISOLIERT beantworten (kein Report-Kontext)

2. **Execute Sub-Workflow: research-verify-factscore** (Sprint 3)
   - Code Node: `python3 research-quality-gate.py --factscore --claims '{{claims_json}}'`
   - Atomare Claims gegen Web-Suche prüfen

3. **Execute Sub-Workflow: research-judge**
   - Execute Command: Gemini CLI — Cross-Model Judge
   ```bash
   gemini -p "Bewerte diesen Research-Report auf 5 Dimensionen (Score 1-5 pro Dimension):
   1. Relevance 2. Accuracy 3. Completeness 4. Bias 5. Actionability
   Report: {{report_summary}}" --sandbox
   ```
   - 5 Dimensionen: Relevance, Accuracy, Completeness, Bias, Actionability
   - Score 1-5 pro Dimension

4. **Code Node** — Verification Table zusammenbauen

### Output
```json
{
  "verification_table": [
    {
      "claim_id": "c-1",
      "text": "...",
      "cove_status": "verified|partially|failed",
      "factscore_status": "SUPPORTED|NOT_SUPPORTED|AMBIGUOUS",
      "judge_score": 4.2,
      "final_status": "verified|partially_verified|refuted|ambiguous",
      "confidence": 0.92
    }
  ],
  "overall": {
    "verified_pct": 85,
    "judge_avg": 4.1,
    "gate3_passed": true
  }
}
```

---

## 12. research-phase4-synthesize

### Nodes
1. **Code Node** — Freshness Check
   - Versionen, Preise, Modellnamen: Aktuell?
   - >12 Monate alte Quellen: `[Stand: YYYY-MM]` markieren

2. **Execute Command** — CLI-basierte Report-Synthese
   - Quick/Standard: Gemini CLI
   - Deep: Claude CLI (Opus) für höchste Qualität
   ```bash
   # Standard:
   gemini -p "Erstelle einen Research-Report nach Template v3: {{verified_data}}" --sandbox
   # Deep:
   claude -p "Erstelle einen Research-Report nach Template v3: {{verified_data}}" --model opus
   ```
   - Template v3: Executive Verdict, PRISMA, Decision Table, Detailanalyse, Gegenrecherche, Widersprüche, Verification Table, Next Action, Open Risks, Quellen
   - Sprache: `{{language}}` (de oder en)

3. **Code Node** — Template v3 Compliance Check
   - Alle Pflicht-Sektionen vorhanden?
   - Claim Verification Table vorhanden?
   - PRISMA Protocol vollständig?

### Output
```json
{
  "report_markdown": "# Research Report ...",
  "title": "...",
  "verdict": "ADOPT|TEST|REJECT",
  "quality_score": 0.87,
  "template_compliant": true
}
```

---

## 13. research-deliver

**Wichtig:** Verwendet den **Research Bot** (dedizierter Telegram Bot, NICHT Nathan Bot).

### Nodes (parallel)
1. **Telegram (Research Bot)** — Report-Summary + Link an Nico (Chat-ID: 827301846)
   - Bot Token: In n8n als "Research Bot" Credential konfiguriert
   - Format: Markdown mit Executive Verdict + Top 3 Findings + Quellen-Count
2. **Google Drive** — Upload Markdown + optional PDF in `Familie/Research/`
3. **HTTP Request** — SurrealDB KB-Writeback
   - INSERT research_report
   - INSERT/UPDATE source_registry (Reputation-Update)
   - INSERT used_source (pro Run)
   - INSERT research_claim (pro Claim)
   - UPDATE research_run SET status = 'completed'
   - Verified Claims (≥T2) → openclaw/knowledge (Sync)
4. **HTTP Request** — OpenClaw Webhook Callback (falls trigger_source = 'openclaw')

---

## 14. research-hitl

**Verwendet den Research Bot** — HITL-Buttons kommen vom Research Bot, kein Konflikt mit Nathan Bot.

### Nodes
1. **Telegram (Research Bot)** — Inline Buttons senden an Nico (827301846)
   - `[✅ Approve] [❌ Reject] [✏️ Edit Query]`
   - Attachment: Report-Preview (erste 500 Zeichen)
   - Bot Token: "Research Bot" Credential

2. **Wait** — Warte auf Telegram Callback Query (Timeout: 24h)

3. **Switch** — Basierend auf Button-Antwort:
   - Approve → Weiter zu research-deliver
   - Reject → SurrealDB UPDATE status = 'failed', reason = 'user_rejected'
   - Edit Query → Zurück zu Phase 0 mit neuem Query

---

## 15. Credentials & CLIs

### CLIs (lokal auf B-Link, Auth bereits konfiguriert)

| CLI | Verwendet in | Aufruf |
|---|---|---|
| `codex` | Phase 0 (Planning) | `codex exec "..."` |
| `gemini` | Phase 1 (Deep), Phase 3 (Judge), Phase 4 (Standard) | `gemini -p "..." --sandbox` |
| `claude` | Phase 2 (Devil's Advocate), Phase 4 (Deep) | `claude -p "..." --model opus` |

### API Keys (in n8n konfiguriert)

| Credential | Typ | Verwendet in |
|---|---|---|
| Brave Search API | API Key | research-search-web |
| Tavily API | API Key | research-search-web |
| xAI/Grok API | API Key | research-search-social |
| You.com API | API Key | research-search-youcom (optional) |
| SurrealDB | HTTP Basic Auth | Alle Status-Updates |
| MiniFlux | API Key | research-search-miniflux |
| Research Bot (Telegram) | Bot Token | research-deliver, research-hitl |
| Google Drive | OAuth | research-deliver |

---

## 16. Bestehende Scripts → n8n Code Nodes

| Script | n8n-Verwendung | Aufruf |
|---|---|---|
| `research.py` | Nicht direkt — Logik in einzelne Sub-Workflows aufgeteilt | — |
| `research-quality-gate.py` | Phase 3 (CoVe, FActScore, Judge) | `python3 research-quality-gate.py --cove\|--factscore\|--judge` |
| `yt-transcript.py` | Phase 1 YouTube Branch | `python3 yt-transcript.py "{{url}}"` |
| `kb-search.py` | Phase 0 (Existenz-Check) + Phase 1 (KB-Branch) | `python3 kb-search.py "{{query}}"` |
| `kb-ingest.py` | Delivery Phase (KB-Writeback) | Via SurrealDB direkt (HTTP Request) |

---

## 17. OpenClaw Skill: `research-workflow`

Neuer Skill in `~/.openclaw/skills/research-workflow/SKILL.md`, damit Nathan den n8n Research-Workflow triggern kann.

### Trigger
Nathan erkennt Research-Anfragen ("recherchiere X", "untersuche Y", "analysiere Z") und nutzt den Skill statt Spock zu spawnen.

### Aktion
```bash
curl -X POST http://localhost:5678/webhook/research-start \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{{research_query}}",
    "domain_hint": "{{domain_or_auto}}",
    "language": "{{detected_language}}",
    "trigger_source": "openclaw",
    "requester": "nico",
    "chat_id": 827301846
  }'
```

### Antwort an Nico
"Research-Auftrag gestartet. Der Report kommt über den Research Bot, sobald er fertig ist."

### Nathan SOUL.md Änderung
```diff
- Nathan recherchiert NICHT selbst. Research-Tasks → IMMER Spock spawnen.
+ Nathan recherchiert NICHT selbst. Research-Tasks → research-workflow Skill triggern (n8n).
+ Spock wird nur noch für Echtzeit-Fragen im Konversationskontext verwendet.
```

**Prinzip:** n8n orchestriert, Scripts machen die Arbeit. Kein Rewrite from scratch.
