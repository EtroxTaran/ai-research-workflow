# Produkt-Vision: AI Research Pipeline

**Projekt:** research-workflow-n8n
**Version:** 3.1 (Monolith-Architektur — implementiert)
**Datum:** 2026-04-10
**Status:** SPRINT 2 ABGESCHLOSSEN — PRODUKTIV

> **Architektur-Update 2026-04-10:** Die in Abschnitt 4 beschriebene Sub-Workflow-Architektur
> (`research-orchestrator`, `research-phase0-plan`, `research-phase1-gather` etc.) wurde **nicht deployed**.
> Stattdessen wurde ein 53-Node Monolith implementiert: `workflows/research-orchestrator-monolith.json`.
> Alle 4 Modi (flash/quick/standard/deep), HITL-Routing, Agent-Callbacks und Web-UI sind aktiv.
> Aktuelle Referenz: `docs/research-modes.md` · `docs/agent-integration.md` · `portal/index.html`

---

## 1. Vision & Purpose

> Eine n8n-basierte Research-Pipeline, die über OpenClaw, Portal oder Telegram angesteuert wird, Recherchen parallel über 6-7 Datenquellen durchführt, mit adaptiven Quality Gates verifiziert, und die Ergebnisse über einen dedizierten Telegram Bot zuliefert — während eine wachsende Quellen-Datenbank die Qualität über Zeit steigert.

### Was es ist
- Ein **n8n-Workflow-System** auf dem B-Link R2D2 Server (Self-Hosted, lokal, 24/7)
- **CLI-first**: Gemini CLI, Claude CLI, Codex CLI statt direkte API-Calls wo möglich
- Ein **Nexus Portal Plugin** (`@nexus/plugin-research`) für Web-basiertes Management
- Ein **OpenClaw Skill** (`research-workflow`) für Nathan-Integration
- Ein **Unified Source System** (ein Namespace) das über Zeit Reputation aufbaut
- **Adaptive Pipeline**: Quick (<2min) / Standard (5-15min) / Deep (15-30min)

### Was es NICHT ist
- Kein Ersatz für OpenClaw — Nathan bleibt Orchestrator, n8n ist Worker
- Kein Real-Time-Chat — asynchroner Batch-Prozess mit Notification
- Kein eigenständiges Produkt — eingebettet ins bestehende Ökosystem

### Warum n8n statt OpenClaw-native?
| Problem (Spock in OpenClaw) | Lösung (n8n) |
|---|---|
| Sequentielle Ausführung | 6-7 Search-Branches parallel |
| Session-Timeouts → Kontextverlust | Persistente Workflows |
| Jeder Run kostet Sonnet/Opus-Tokens | CLI-basiert (Subscriptions/Free Tiers) |
| Cron-Jobs mit Fehler-History (42 broken) | Zuverlässige Schedule Triggers |
| Kein Audit-Trail | Execution History automatisch |
| Kein strukturierter HITL | Telegram Inline Buttons |

### Warum CLI-first statt direkte APIs?
| API-Ansatz | CLI-Ansatz |
|---|---|
| Pay-per-Token für jede LLM-Nutzung | Subscriptions/Free Tiers der CLIs |
| Eigenes Auth-Management pro Provider | CLI-Auth bereits lokal konfiguriert |
| HTTP Request Nodes + Error Handling | Execute Command Node, einheitlich |
| 5+ API-Keys managen | CLIs nutzen bestehende Sessions |

---

## 2. System-Architektur

```
┌─────────────────────────────────────────────────────────────────────┐
│                          TRIGGER LAYER                               │
│                                                                       │
│  Nico ──→ Nathan (OpenClaw) ──→ Skill: research-workflow ──┐        │
│  Portal ──→ "Neue Recherche" Button ───────────────────────┤        │
│  Schedule ──→ Weekly Digest / Monitoring ──────────────────┤        │
│  Research Bot ──→ Telegram Direct Message ─────────────────┘        │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ POST /webhook/research-start
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│              n8n RESEARCH WORKFLOW (B-Link R2D2, lokal)              │
│                                                                       │
│  Phase 0 (Plan + Modus-Klassifizierung) → Quick/Standard/Deep       │
│  Phase 1 (6-7 Branches parallel) → Gate 1 (Standard/Deep)          │
│  Phase 2 (Counter-Research) → Gate 2 (nur Deep)                     │
│  Phase 3 (CoVe + FActScore + Judge) → Gate 3 (Standard/Deep)       │
│  Phase 4 (Synthesis) → Quality Gate → Deliver / HITL / Retry        │
└──────────────┬──────────────────────────────┬───────────────────────┘
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌────────────────────────────────────┐
│   SurrealDB (Unified)    │    │   DELIVERY                          │
│   research/workflow      │    │   Research Bot → Telegram (Reports) │
│   (Runs, Reports,        │    │   Google Drive → Archiv             │
│    Sources, Creators,    │    │   SurrealDB → Portal Live-Status    │
│    Claims — MASTER)      │    └────────────────────────────────────┘
│                          │
│   openclaw/knowledge     │
│   (← Edge-Referenz auf   │
│    verified Claims ≥T2)  │
└──────────────────────────┘
```

### Zwei-Bot-Architektur
| Bot | System | Zweck |
|---|---|---|
| **Nathan Bot** (ID: 8213463852) | OpenClaw | Konversation mit Nico — Chat, Fragen, Delegation |
| **Research Bot** (Token: konfiguriert) | n8n | Research-Reports, HITL-Buttons, Status-Updates |

Kein Polling-Konflikt: Jeder Bot wird von genau einem System gepollt.

### Unified Source System (SurrealDB)
| Namespace | Rolle | Inhalt |
|---|---|---|
| `research/workflow` | **Master** | research_run, research_report, source_registry, creator, research_claim, used_source |
| `openclaw/knowledge` | **Referenz** | Verified Claims (≥T2) werden per Edge-Referenz verlinkt, nicht dupliziert |

**Prinzip:** Ein Source-System, eine Wahrheit. `openclaw/knowledge` referenziert `research/workflow.source_registry` per ID — kein Duplikat, kein Sync-Konflikt.

---

## 3. Research-Prozess — 5 Phasen (Adaptiv)

### Adaptive Pipeline-Tiefe

Phase 0 klassifiziert jede Query automatisch. User kann Modus überschreiben: `"Recherchiere [deep]: Beste GraphDB"`

| Modus | Auslöser | Branches | Gates | CLIs/LLMs | Kosten | Dauer |
|-------|----------|----------|-------|-----------|--------|-------|
| **Quick** | Einfache Fakten, kurze Fragen | KB + Web + Gemini Grounding | Nur Gate 4 | Gemini CLI | ~$0.02 | <2 min |
| **Standard** | Vergleiche, Analysen | Alle 6 Branches | Gate 1 + 3 + 4 | Gemini CLI + Codex CLI | ~$0.30-0.80 | 5-15 min |
| **Deep** | Investitionen, Tech-Evaluierungen | Alle 7 Branches + Counter + Full Verify | Alle 4 Gates + HITL | Alle CLIs + Grok API | ~$1-3 | 15-30 min |

### Phase 0 — PRISMA Setup & DAG Planning + Modus-Klassifizierung

| | |
|---|---|
| **Input** | Research Query (natürliche Sprache) + optionaler Kontext + optionaler Modus-Override |
| **Output** | Strukturierter Search Plan (JSON: Sub-Fragen, Suchbegriffe DE+EN, Source-Typen, Scope) + **Modus (Quick/Standard/Deep)** |
| **CLI** | Codex CLI (`codex exec`) |
| **Gate 0** | Search Plan vorhanden, ≥3 Quellen-Typen definiert, Sprache erkannt, Modus klassifiziert |
| **n8n Workflow** | `research-phase0-plan` |

Enthält: Query-Analyse, Domain-Klassifikation (`tech|finance|academic|product_comparison|travel|general`), Sprach-Erkennung (DE/EN), Komplexitäts-Klassifizierung, KB-Existenz-Check.

### Phase 1 — Parallele Datensammlung

6-7 Search-Branches laufen parallel in n8n (je nach Modus):

| Branch | Tool | CLI/API | Sprint | Modus |
|---|---|---|---|---|
| A: KB Search | SurrealDB (`kb-search.py`) | Execute Command | 1 | Alle |
| B: Web Search | Brave + Tavily (parallel) | HTTP Request | 1 | Alle |
| C: Deep Research | Gemini CLI mit Google Search Grounding | Execute Command | 2 | Standard + Deep |
| D: Social/Real-Time | Grok 4 API DeepSearch | HTTP Request | 2 | Standard + Deep |
| E: Academic | Semantic Scholar + ArXiv | HTTP Request | 3 | Standard + Deep |
| F: MiniFlux RSS | MiniFlux REST API | HTTP Request | 1 | Alle |
| G: Deep Research (optional) | You.com Research API | HTTP Request | 3 | Nur Deep |

**YouTube** wird über Gemini CLI (Branch C) oder `yt-transcript.py` abgedeckt.

| | |
|---|---|
| **Output** | Gesammelte Quellen + extrahierte Claims (strukturiertes JSON) |
| **Gate 1** | Quick: —, Standard: ≥8 Quellen ≥2 Plattformen, Deep: ≥12 Quellen ≥3 Plattformen ≥5 T1/T2 |
| **n8n Workflow** | `research-phase1-gather` + Sub-Workflows pro Branch |

### Phase 2 — Gegenrecherche + Devil's Advocate (Standard/Deep)

| | |
|---|---|
| **Input** | Claims aus Phase 1 |
| **Output** | Counter-Evidence, Devil's Advocate Argumente, Widersprüche-Tabelle |
| **CLI** | Claude CLI mit Opus (`claude -p --model opus`) für Devil's Advocate + Pre-Mortem |
| **Gate 2** | ≥80% Kernaussagen haben Counter-Research, Widersprüche dokumentiert |
| **n8n Workflow** | `research-phase2-counter` |
| **Sprint** | 2 |
| **Modus** | Nur Standard (light) + Deep (full) |

### Phase 3 — Claim-Level Verification (Standard/Deep)

Drei Methoden, kombiniert (Standard: nur CoVe, Deep: alle drei):

| Methode | Beschreibung | Tool | Modus |
|---|---|---|---|
| **CoVe** (Chain-of-Verification) | Claims isoliert verifizieren, Konsistenz prüfen | `research-quality-gate.py --cove` | Standard + Deep |
| **FActScore** | Atomare Aussagen gegen Web-Suche prüfen | `research-quality-gate.py --factscore` | Nur Deep |
| **LLM-as-Judge** | Cross-Model-Bewertung (5 Dimensionen, Score 1-5) | Gemini CLI (Cross-Model) | Standard + Deep |

| | |
|---|---|
| **Output** | Verification Table (Status pro Claim: VERIFIED / PARTIALLY / REFUTED) |
| **Gate 3** | Standard: ≥70% verified, Deep: ≥80% verified + Judge-Score ≥3.5 |
| **n8n Workflows** | `research-verify-cove`, `research-verify-factscore`, `research-judge` |
| **Sprint** | 2 (CoVe + Judge), 3 (FActScore) |

### Phase 4 — Freshness + Synthese + Quality Gate

| | |
|---|---|
| **Input** | Verified Claims + Quellen + Counter-Evidence + Verification Table |
| **Output** | Finaler Research Report (Markdown, Template v3) |
| **CLI** | Claude CLI mit Opus (Deep) oder Gemini CLI (Quick/Standard) |
| **Sprache** | Automatisch: DE Query → DE Report, EN Query → EN Report |
| **n8n Workflow** | `research-phase4-synthesize` |

**Quality Gate Entscheidung:**
```
IF gate == PASS AND confidence ≥ 75%  → Deliver
IF gate == PASS AND confidence < 75%  → Deliver mit HITL Approval Request
IF gate == FAIL AND retries < 3       → Replan (schwächste Phase wiederholen)
IF gate == FAIL AND retries ≥ 3       → HITL Escalation
```

---

## 4. n8n Sub-Workflows

| Workflow | Funktion | Sprint |
|---|---|---|
| `research-orchestrator` | Main: Trigger → Phasen → Gates → Delivery | 1 |
| `research-phase0-plan` | Query → Search Plan + Domain + Sprache | 1 |
| `research-phase1-gather` | Parallel-Dispatch + Merge + Dedup + Gate 1 | 1 |
| `research-search-kb` | SurrealDB Hybrid-Search | 1 |
| `research-search-web` | Brave + Tavily (parallel) | 1 |
| `research-search-miniflux` | MiniFlux REST API | 1 |
| `research-search-deep` | Gemini CLI (Search Grounding) | 2 |
| `research-search-social` | Grok 4 API DeepSearch | 2 |
| `research-search-academic` | Semantic Scholar + ArXiv | 3 |
| `research-search-youcom` | You.com Research API (optional, Deep) | 3 |
| `research-phase2-counter` | Devil's Advocate + Counter-Search | 2 |
| `research-phase3-verify` | CoVe + FActScore + Judge Orchestrierung | 2 |
| `research-phase4-synthesize` | Freshness + Report Template v3 | 1 |
| `research-deliver` | Research Bot + Drive + SurrealDB + KB-Sync | 1 |
| `research-hitl` | Telegram Inline Buttons + Approval | 2 |

Detaillierte Node-Specs: [`docs/n8n-workflow-specs.md`](./docs/n8n-workflow-specs.md)

---

## 5. CLI-first Strategie

### Verfügbare CLIs (auf B-Link R2D2)

| CLI | Version | Auth | Nutzung |
|---|---|---|---|
| `gemini` | v0.32.1 | Google API Key | Deep Research (Search Grounding), Synthesis, Judge |
| `claude` | v2.1.92 | Anthropic Key | Counter-Research (Opus), Synthesis (Deep) |
| `codex` | v0.112.0 | OpenAI Key | Planning, Query Decomposition, Web Analysis |

### Phasen-Zuordnung

| Phase | CLI/Tool | Begründung |
|---|---|---|
| Phase 0 (Planning) | Codex CLI | Schnell, guter Structured Output |
| Phase 1 (Deep Research) | Gemini CLI (Search Grounding) | Google-Index, 5K free/Mo, ersetzt Perplexity |
| Phase 1 (Social) | Grok 4 API | Native X/Twitter-Zugang, kein CLI verfügbar |
| Phase 1 (Web Search) | Brave + Tavily APIs | HTTP Request Nodes (kein CLI nötig) |
| Phase 2 (Devil's Advocate) | Claude CLI (Opus) | Stärkstes adversariales Reasoning |
| Phase 3 (CoVe + FActScore) | `research-quality-gate.py` | Bestehendes Script, kein LLM nötig |
| Phase 3 (Judge) | Gemini CLI | Cross-Model-Validation (anderer Provider!) |
| Phase 4 (Quick/Standard) | Gemini CLI | Kosteneffizient für Standard-Reports |
| Phase 4 (Deep) | Claude CLI (Opus) | Höchste Qualität für Investitionsentscheidungen |
| Quality Gate Scripts | Python (kein LLM) | Deterministische Strukturchecks |

### CLI-Aufrufe in n8n (Execute Command Nodes)

```bash
# Phase 0: Query Decomposition
codex exec "Zerlege diese Forschungsfrage in Sub-Fragen und klassifiziere den Modus: ${query}"

# Phase 1: Deep Research mit Google Grounding
gemini -p "Recherchiere umfassend mit Web-Quellen: ${query}. Gib alle Quellen-URLs an."

# Phase 2: Devil's Advocate
claude -p "Du bist ein kritischer Analyst. Finde die 5 stärksten Gegenargumente: ${claims}" --model opus

# Phase 3: Cross-Model Judge
gemini -p "Bewerte diesen Research-Report auf 5 Dimensionen (1-5): ${report}"

# Phase 4: Synthesis
claude -p "Erstelle einen Research-Report nach Template v3: ${verified_claims}" --model opus
```

**Prinzip:** CLI-first (Subscriptions/Free Tiers), API nur wo kein CLI vorhanden (Grok, Brave, Tavily). Cross-Model für Verification.

---

## 6. Such-Tools & Datenquellen

### Kosten-Übersicht (~$5-20/Monat)

| Tool | Typ | Kosten/Monat | Integration | Sprint |
|---|---|---|---|---|
| **Brave Search** | Web | $5 Credit (1K free) | HTTP Request | 1 |
| **Tavily Search + Extract** | Web | $0 Free Tier (1K/Mo) | HTTP Request | 1 |
| **Gemini CLI + Search Grounding** | Deep Research | $0 (5K free/Mo) | Execute Command | 2 |
| **Grok 4 API DeepSearch** | Social/X | ~$5-15 (usage) | HTTP Request | 2 |
| **You.com Research API** | Deep Research | $0 ($100 Credit ≈ 15 Mo) | HTTP Request | 3 |
| **Semantic Scholar** | Academic | $0 (kostenlos) | HTTP Request | 3 |
| **ArXiv** | Academic | $0 (kostenlos) | HTTP Request | 3 |
| **MiniFlux RSS** | News/RSS | $0 (Self-Hosted) | HTTP Request | 1 |
| **SurrealDB KB** | Knowledge Base | $0 (Self-Hosted) | Execute Command | 1 |

### Spätere Erweiterung
| Tool | Typ | Mehrwert |
|---|---|---|
| Exa | Semantic Neural Search | Discovery-Queries (1K free/Mo) |
| Firecrawl | Full-Page Extraction | Wenn Tavily Extract nicht reicht |
| OpenAlex + CrossRef | Academic | Breitere Abdeckung, Citation Verification |

---

## 7. Qualifiziertes Quellen-System

### Reputation Lifecycle

```
ENTDECKUNG                          BEWERTUNG                      REPUTATION                    NUTZUNG
├── Research findet Quelle          ├── Gate 1: Credibility       ├── Score berechnen:          ├── Trusted Sources priorisiert
│   → source_registry               │   Scoring                   │   (correct+1)/              │   in Phase 1
│   (T3, reputation: 0.5)          ├── Gates 2-4: Claims          │   (correct+incorrect+2)     ├── Gewichtung in Synthese
├── MiniFlux-Feed                   │   überleben → correct++     ├── >0.8 nach 3+ Runs:       └── Portal: Filter/Sort
│   → Auto-T2, reputation: 0.7    └── Claims fallen              │   Auto-Vorschlag Trusted        nach Reputation
├── Creator-Registry                    durch → incorrect++        └── <0.3: Auto-Downgrade
│   → trust per creator
└── Portal: Manuell
```

### Source Registry
Alle jemals gefundenen Quellen mit URL, Domain, Trust Level, Reputation Score, Correct/Incorrect Counts, Tags. Portal-UI zum Verwalten (Trust ändern, blockieren, Tags editieren).

### Creator Registry
Kuratierte Content Creators über alle Plattformen: YouTube, X, LinkedIn, Substack, Reddit, Blog, RSS, Podcast. Pro Creator: Name, Platform, Channel URL, Trust Level (high/medium/watch), Domain Tags, Active-Status. Auto-Discovery Queue mit HITL-Approval.

---

## 8. SurrealDB Schema

**Namespace:** `research/workflow`
**Schema-Datei:** [`schema/research-workflow.surql`](./schema/research-workflow.surql)

| Tabelle | Beschreibung |
|---|---|
| `research_run` | Research-Runs mit Status, Scores, Kosten, Manifest |
| `research_report` | Reports (Markdown, Quality Score, User Rating, NotebookLM ID) |
| `source_registry` | Quellen-Registry mit Reputation-Tracking |
| `creator` | Content Creator Registry (Multi-Platform) |
| `used_source` | Quellen-pro-Run Verknüpfung (Edge-Table) |
| `research_claim` | Claims mit Verification-Status (CoVe, FActScore, Judge) |

---

## 9. Web UI — Nexus Portal Plugin

**Plugin:** `@nexus/plugin-research` im Nexus Portal (`~/projects/ai-portal/`)
**Spezifikation:** [`portal/PLUGIN-SPEC.md`](./portal/PLUGIN-SPEC.md)

| Screen | Route | Sprint |
|---|---|---|
| Research Dashboard | `/research` | 1 |
| Report Viewer | `/research/runs/:runId` | 1 |
| Source Registry | `/research/sources` | 2 |
| Creator Registry | `/research/creators` | 2 |
| Neue Recherche | `/research/new` | 2 |

**Integration:** Portal triggert n8n via Webhook, pollt SurrealDB für Live-Status (TanStack Query, 5s Intervall während Run aktiv).

---

## 10. Delivery & HITL

### Delivery-Kanäle
| Kanal | Format | Wann |
|---|---|---|
| Research Bot (Telegram) | Report-Summary + Markdown | Immer |
| Google Drive | Markdown + optional PDF | Immer |
| SurrealDB | Strukturierte Daten (Run, Report, Claims, Sources) | Immer |
| openclaw/knowledge | Verified Claims (≥T2) | Bei PASS |

### HITL-Trigger
| Situation | Aktion | Kanal |
|---|---|---|
| Confidence < 60% nach Verification | Approval Request mit Preview | Research Bot: Inline Buttons |
| High-Stakes Domain (Finanzen, Recht, Medizin) | Mandatory Review | Research Bot: Inline Buttons |
| ≥30% Claims NICHT VERIFIZIERT | Report + Failure-Details | Research Bot |
| Quality Gate FAIL nach 3 Retries | Escalation mit Diagnose | Research Bot |
| Widersprüche ohne Auflösung | Entscheidungsvorlage | Research Bot: Inline Buttons |

**Buttons:** `[✅ Approve]` `[❌ Reject]` `[✏️ Edit Query]` — Timeout: 24h → Auto-Reject.

---

## 11. Spezial-Modi (Sprint 4)

### Weekly Digest (Multi-Domain)
Schedule: **Sonntag 08:00** → Für jeden konfigurierten Domain-Kanal:
1. MiniFlux: Ungelesene Entries der Woche filtern nach Domain
2. Creator Monitor: Neue Inhalte der Woche von tracked Creators
3. KB: Neue Claims der Woche aggregieren
4. Gemini CLI: Zusammenfassung der wichtigsten Entwicklungen
5. Research Bot → Telegram: Domain-Digest

**Konfigurierbare Kanäle** (in SurrealDB):
- **Tech/AI**: AI-News, Framework-Releases, Tool-Updates
- **Finanzen**: Marktentwicklungen, Portfoliorelevantes
- **Branchen-News**: Konfigurierbar pro Interesse

### Produktvergleich
Trigger: "X vs Y" / "bestes Z für [Zweck]" → Kriterien-Matrix → Pro-Kandidat-Suche + Head-to-Head → Negative Reviews → Vergleichstabelle + Entscheidungsmatrix.

### Continuous Monitoring
Schedule: Täglich/6h für definierte Topics → Delta-Only (nur Neues seit letztem Run) → Novelty-Score > 0.7 → Notification. Akkumuliert in SurrealDB.

### Domain-Routing
Phase 0 klassifiziert den Query und passt an: Source-Gewichtung, Creator-Filter, MiniFlux-Kategorien, Verification-Strenge (Finance/Medical = mandatory HITL).

---

## 12. NotebookLM Integration

| Phase | Feature | Sprint |
|---|---|---|
| 1 | Export: Optimiertes Markdown + Verified Sources als Paket | 4 |
| 2 | Direkte API: Apify NotebookLM Actor, Auto-Notebook-Erstellung | 5 |
| 3 | Bidirektional: NotebookLM-Insights zurück in KB | Später |

---

## 13. OpenClaw Integration

### Skill: `research-workflow`
| | |
|---|---|
| **Pfad** | `~/.openclaw/skills/research-workflow/SKILL.md` |
| **Trigger** | "recherchiere", "research", "untersuche", "analysiere [Topic]" |
| **Aktion** | HTTP POST → `localhost:5678/webhook/research-start` (B-Link n8n) |
| **Body** | `{query, domain_hint, language, trigger_source: "openclaw"}` |
| **Antwort** | "Research-Auftrag gestartet. Report kommt über den Research Bot." |

### Nathan SOUL.md Anpassung
Bisherige Regel: "Nathan recherchiert NICHT selbst → Spock spawnen"
Neue Regel: "Nathan recherchiert NICHT selbst → `research-workflow` Skill triggern → n8n macht die Arbeit"

### Migrations-Roadmap (nach Research-Workflow)
1. **MiniFlux Sync** → n8n (Sample-Workflow existiert bereits)
2. **KB Population Pipeline** → n8n (kb-claim-extractor + verifier + contradiction-detector)

---

## 14. Error Handling & Resilience

### Fallback-Ketten
| Node-Typ | Primary | Fallback 1 | Fallback 2 |
|---|---|---|---|
| Search (Web) | Brave | Tavily | Gemini Grounding |
| Search (Deep) | Gemini CLI | You.com API | Brave + Tavily |
| Search (Social) | Grok API | Tavily (News) | — |
| CLI (Planning) | Codex CLI | Gemini CLI | Claude CLI |
| CLI (Judge) | Gemini CLI | Claude CLI | Codex CLI |
| CLI (Synthese) | Claude CLI (Opus) | Gemini CLI | Codex CLI |

### Retry-Strategie
| Fehler | Aktion |
|---|---|
| 429 Rate Limit | Exponential Backoff (1s→2s→4s→8s, max 30s) |
| 5xx Server Error | 3 Retries mit 5s Pause |
| 401/403 Auth Error | Kein Retry — sofort Fallback-Provider |
| Timeout | Node-spezifisch (Search: 60s, LLM: 120s, Quality Gate: 300s) |

### Circuit Breaker
Provider 3× hintereinander gefailed → 15min Cooldown → nur Fallback → Telegram-Notification.

---

## 15. Implementierungs-Roadmap

### Sprint 1 — MVP Pipeline (KW 15-16)

**Tag 1: Infrastruktur**
- SurrealDB `research/workflow` Namespace + Unified Schema deployen
- Research Bot Token in n8n konfigurieren
- n8n Credentials: Brave, Tavily, SurrealDB, MiniFlux
- CLIs testen: `gemini -p`, `claude -p`, `codex exec` auf B-Link

**Tag 2-5: n8n Workflows**
- `research-orchestrator` (Webhook + Manual Trigger + Adaptive Routing)
- `research-phase0-plan` (Codex CLI: Query → Search Plan + Modus-Klassifizierung)
- `research-search-web` + `research-search-kb` + `research-search-miniflux`
- `research-phase1-gather` (Parallel → Merge → Dedup)
- `research-phase4-synthesize` (Gemini CLI, Template v3)
- `research-deliver` (Research Bot + SurrealDB)

**Tag 5-6: OpenClaw Integration**
- Skill `research-workflow` erstellen
- Nathan SOUL.md anpassen

**Tag 6-7: Test**
- E2E-Run: "Vergleich React vs. Svelte 2026" (Quick + Standard Modi)
- Report via Research Bot empfangen
- Run in SurrealDB gespeichert

**Gate:** 1 Research-Run E2E, Report via Research Bot zugestellt

### Sprint 2 — Verification + Search Expansion (KW 16-17)
- Gemini CLI Search Grounding Branch (Deep Research Ersatz)
- Grok 4 API DeepSearch Branch (Social/X)
- Phase 2 (Counter-Research: Claude CLI Opus)
- Phase 3 (CoVe via research-quality-gate.py + Judge via Gemini CLI)
- Adaptive Pipeline-Tiefe Routing (Quick/Standard/Deep)
- Gate-Logik (Pass/Fail/Retry)
- HITL (Telegram Inline Buttons)

**Gate:** Quality Gate automatisch, Quellen in Portal verwaltbar

### Sprint 3 — Full Stack (KW 17-18)
- Academic Branch (Semantic Scholar + ArXiv)
- You.com Research API Branch (optional, Deep-Modus)
- YouTube Integration (yt-transcript.py + Gemini Summarization)
- FActScore
- Source-Reputation-Tracking
- KB-Writeback (Claims → openclaw/knowledge)
- Fallback-Ketten + Circuit Breaker
- Portal: Source Detail + Quality Badges + User-Rating + Kosten

**Gate:** 5 Runs < 30min, ≥80% Claims verified, Portal voll nutzbar

### Sprint 4 — Spezial-Modi + Portal (KW 18-19)
- Weekly Digest Workflow (Multi-Domain, Schedule Trigger)
- Produktvergleich + Domain-Modi
- Feedback-Loop (Rating → Prompt-Optimierung)
- Portal: Export (Markdown/PDF/NotebookLM) + Creator CRUD + Stats

### Sprint 5 — Optimierung (KW 19-20)
- Caching-Layer (ähnliche Queries → cached Results in SurrealDB)
- MCP Server Node (n8n als Tool für Claude Code — bidirektional)
- Source Feedback Loop (👍/👎 → Reputation)
- Creator Discovery Agent
- Exa Integration (Semantic Neural Search)
- NotebookLM API-Integration

---

## 16. Metriken & Erfolgskriterien

| Metrik | Target | Messung |
|---|---|---|
| Strukturierte Recherche | 100% Reports folgen Prozess | Template v3 Compliance |
| Claim Verification Rate | ≥80% Claims verified | Verified / Total Claims |
| Quellenqualität | ≥10 Quellen, ≥3 Plattformen | Pro Report |
| Durchlaufzeit | <30 Minuten | 90th Percentile |
| Gate Pass Rate | ≥70% First-Pass | First-Pass / Total Runs |
| HITL Trigger Rate | <15% | HITL-Runs / Total |
| KB Growth | ≥5 verifizierte Claims | Pro Report |
| User Satisfaction | ≥85% positiv | 👍/👎 Bewertung |
| Cost per Report | Tracking (kein festes Ziel) | Token-Kosten pro Phase |

---

## 17. Bereitgestellte Ressourcen

### CLIs (auf B-Link R2D2)
| CLI | Version | Status |
|---|---|---|
| `gemini` | v0.32.1 | ✅ Installiert, Auth konfiguriert |
| `claude` | v2.1.92 | ✅ Installiert, Auth konfiguriert |
| `codex` | v0.112.0 | ✅ Installiert, Auth konfiguriert |

### API Keys (in `~/.openclaw/.env`)
| Service | Kosten | Status |
|---|---|---|
| Brave Search | $5/Mo Credit | ✅ |
| Tavily | Free Tier (1K/Mo) | ✅ |
| Grok/xAI | Usage-based | ✅ |
| You.com Research | $100 Free Credit | 🔧 Einrichten |
| MiniFlux | Self-Hosted | ✅ |
| SurrealDB | Self-Hosted | ✅ |
| Research Bot (Telegram) | Kostenlos | ✅ |

### Infrastruktur (B-Link R2D2 — lokal, 24/7)
| System | URL / Port | Status |
|---|---|---|
| n8n | Docker `n8n-local`, `localhost:5678` (B-Link R2D2) | ✅ Läuft |
| SurrealDB | `localhost:8001` | ✅ Läuft, v3.0.0 |
| MiniFlux | `example.com` (Migration geplant) | ✅ Läuft |
| Nexus Portal | `~/projects/ai-portal/` | ✅ Walking Skeleton ready |

### Bestehende Scripts (wiederverwenden)
| Script | Zeilen | Funktion | n8n-Verwendung |
|---|---|---|---|
| `research-quality-gate.py` | ~1040 | CoVe + FActScore + Judge | Phase 3 (Code Node) |
| `kb-search.py` | ~300 | Hybrid GraphRAG Search | Phase 1 KB-Branch |
| `yt-transcript.py` | ~200 | YouTube Transkription | Phase 1 YouTube-Branch |
| `kb-miniflux-sync.py` | — | MiniFlux → SurrealDB Sync | Phase 1 MiniFlux-Branch |

### Dokumentation
| Datei | Inhalt |
|---|---|
| `docs/n8n-workflow-specs.md` | Technische Sub-Workflow-Spezifikationen |
| `schema/research-workflow.surql` | SurrealDB Schema (direkt deploybar) |
| `portal/PLUGIN-SPEC.md` | Nexus Portal Plugin-Spezifikation |
| `docs/ai-research-workflow-multi-agent-n8n.md` | Research Report: Multi-Agent Architektur |
| `docs/perplexity-research-workflow.md` | Research Report: Perplexity + Research Process |
