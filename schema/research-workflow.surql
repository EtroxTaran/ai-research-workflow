-- ============================================================================
-- Research Workflow — SurrealDB Schema
-- Namespace: research/workflow
-- Version: 2.0.0 (Unified Source Model)
-- Erstellt: 2026-04-06
-- ============================================================================
--
-- UNIFIED SOURCE MODEL:
--   research/workflow ist der MASTER für alle Quellen, Claims und Runs.
--   openclaw/knowledge referenziert source_registry per ID (Edge-Referenz),
--   keine Duplikation. Verified Claims (≥T2) werden per Edge verlinkt.
--
-- Anwenden:
--   surreal import --conn http://localhost:8001 \
--     --user techLeadAgent --pass <password> \
--     --ns research --db workflow \
--     schema/research-workflow.surql
--
-- ============================================================================

-- ============================================================================
-- RESEARCH RUNS — Manifest + Status für Live-Tracking
-- ============================================================================

DEFINE TABLE research_run SCHEMAFULL;

DEFINE FIELD query ON research_run TYPE string
  COMMENT "Original-Query in natürlicher Sprache";
DEFINE FIELD domain ON research_run TYPE string
  ASSERT $value IN ["tech", "finance", "academic", "product_comparison", "travel", "general"]
  COMMENT "Automatisch klassifiziert in Phase 0";
DEFINE FIELD language ON research_run TYPE string
  ASSERT $value IN ["de", "en"]
  COMMENT "Auto-detected aus Query-Sprache";
DEFINE FIELD status ON research_run TYPE string
  ASSERT $value IN ["pending", "phase0", "phase1", "phase2", "phase3", "phase4", "quality_gate", "completed", "failed", "hitl_pending"]
  COMMENT "Aktueller Phase-Status für Portal Live-Tracking";
DEFINE FIELD mode ON research_run TYPE string DEFAULT "standard"
  ASSERT $value IN ["quick", "standard", "deep", "weekly_digest", "product_comparison", "continuous_monitor"]
  COMMENT "Pipeline-Tiefe: quick (<2min), standard (5-15min), deep (15-30min) + Spezial-Modi";

-- Phase 0 Output
DEFINE FIELD search_plan ON research_run TYPE option<object>
  COMMENT "Strukturierter Search Plan (Sub-Questions, Sources, Terms)";
DEFINE FIELD sub_questions ON research_run TYPE option<array>
  COMMENT "DAG der Sub-Fragen aus Phase 0";

-- Config + Kosten
DEFINE FIELD config ON research_run TYPE option<object>
  COMMENT "Model versions, agent configs, thresholds pro Run";
DEFINE FIELD cost ON research_run TYPE option<object>
  COMMENT "Token counts + geschätzte Kosten pro Phase";

-- Gate-Ergebnisse
DEFINE FIELD scores ON research_run TYPE option<object>
  COMMENT "Gate-Scores, Claim Verification Rates, Judge-Scores";
DEFINE FIELD retry_count ON research_run TYPE int DEFAULT 0
  COMMENT "Anzahl Replan-Loops (max 3)";
DEFINE FIELD failed_phase ON research_run TYPE option<string>
  COMMENT "Welche Phase bei Retry fehlgeschlagen ist";

-- n8n Workflow Fields
DEFINE FIELD run_id ON research_run TYPE string
  COMMENT "Unique run identifier from n8n (run_TIMESTAMP)";
DEFINE FIELD source_count ON research_run TYPE option<int>;
DEFINE FIELD claim_count ON research_run TYPE option<int>;
DEFINE FIELD quality_score ON research_run TYPE option<float>;
DEFINE FIELD confidence_score ON research_run TYPE option<float>;
DEFINE FIELD verdict ON research_run TYPE option<string>;

-- Phase 2: Counter-Research
DEFINE FIELD counter_coverage ON research_run TYPE option<float>
  COMMENT "Prozent der Claims mit Counter-Research (0-100)";
DEFINE FIELD gate2_passed ON research_run TYPE option<bool>
  COMMENT "Gate 2: >= 80% Counter-Coverage";

-- Phase 3: Verification
DEFINE FIELD verification ON research_run TYPE option<object>
  COMMENT "P3 Verification-Ergebnisse (CoVe, Judge, FactScore)";
DEFINE FIELD gate3_passed ON research_run TYPE option<bool>
  COMMENT "Gate 3: Verification bestanden";
DEFINE FIELD judge_score ON research_run TYPE option<float>
  COMMENT "LLM-as-Judge Score 0.0-5.0";

-- Timestamps + Links
DEFINE FIELD started_at ON research_run TYPE datetime;
DEFINE FIELD completed_at ON research_run TYPE option<datetime>;
DEFINE FIELD report_id ON research_run TYPE option<record<research_report>>;
DEFINE FIELD n8n_execution_id ON research_run TYPE option<string>
  COMMENT "n8n Execution ID für Debugging-Link";
DEFINE FIELD trigger_source ON research_run TYPE string
  ASSERT $value IN ["webhook", "schedule", "telegram", "manual", "portal", "openclaw"]
  COMMENT "Wie wurde der Run ausgelöst";

-- Indices
DEFINE INDEX idx_status ON research_run FIELDS status;
DEFINE INDEX idx_domain ON research_run FIELDS domain;
DEFINE INDEX idx_started ON research_run FIELDS started_at;

-- ============================================================================
-- RESEARCH REPORTS — Finaler Output
-- ============================================================================

DEFINE TABLE research_report SCHEMAFULL;

DEFINE FIELD run_id ON research_report TYPE record<research_run>;
DEFINE FIELD title ON research_report TYPE string;
DEFINE FIELD content_markdown ON research_report TYPE string
  COMMENT "Vollständiger Report in Markdown (Template v3)";
DEFINE FIELD verdict ON research_report TYPE option<string>
  ASSERT $value IN ["ADOPT", "TEST", "REJECT", none]
  COMMENT "Entscheidungsempfehlung für Evaluations";
DEFINE FIELD template_version ON research_report TYPE string DEFAULT "v3";
DEFINE FIELD synthesis_engine ON research_report TYPE option<string>
  COMMENT "Welche LLM Engine den Report erstellt hat (gemini/claude)";

-- Qualitäts-Metriken
DEFINE FIELD quality_score ON research_report TYPE float
  COMMENT "Gesamt-Qualitätsscore 0.0-1.0";
DEFINE FIELD claim_count ON research_report TYPE int;
DEFINE FIELD verified_claim_count ON research_report TYPE int;
DEFINE FIELD source_count ON research_report TYPE int;
DEFINE FIELD platform_count ON research_report TYPE int
  COMMENT "Anzahl verschiedener Plattformen (Ziel: ≥3)";

-- User-Feedback
DEFINE FIELD user_rating ON research_report TYPE option<string>
  ASSERT $value IN ["thumbs_up", "thumbs_down", none]
  COMMENT "Nico's Bewertung für Feedback-Loop";
DEFINE FIELD user_feedback ON research_report TYPE option<string>
  COMMENT "Freitext-Feedback";

-- External Links
DEFINE FIELD notebooklm_id ON research_report TYPE option<string>
  COMMENT "NotebookLM Notebook ID nach Export";
DEFINE FIELD google_drive_url ON research_report TYPE option<string>
  COMMENT "Google Drive Link zum archivierten Report";

-- Timestamps
DEFINE FIELD created_at ON research_report TYPE datetime;

-- Indices
DEFINE INDEX idx_run ON research_report FIELDS run_id;
DEFINE INDEX idx_quality ON research_report FIELDS quality_score;
DEFINE INDEX idx_created ON research_report FIELDS created_at;

-- ============================================================================
-- SOURCE REGISTRY — Alle jemals gefundenen Quellen, wachsend über Zeit
-- ============================================================================

DEFINE TABLE source_registry SCHEMAFULL;

DEFINE FIELD url ON source_registry TYPE string;
DEFINE FIELD domain ON source_registry TYPE string
  COMMENT "Extrahierte Domain (z.B. arxiv.org, reddit.com)";
DEFINE FIELD title ON source_registry TYPE option<string>;
DEFINE FIELD source_type ON source_registry TYPE string
  ASSERT $value IN ["web", "academic", "social", "youtube", "rss", "creator"]
  COMMENT "Kategorie der Quelle";

-- Trust + Reputation
DEFINE FIELD trust_level ON source_registry TYPE string DEFAULT "T3"
  ASSERT $value IN ["T1", "T2", "T3", "untrusted"]
  COMMENT "T1=höchstes Vertrauen, T3=unbekannt, untrusted=blockiert/schlecht";
DEFINE FIELD is_trusted ON source_registry TYPE bool DEFAULT false
  COMMENT "Manuell als Trusted markiert (via Portal)";
DEFINE FIELD is_blocked ON source_registry TYPE bool DEFAULT false
  COMMENT "Manuell blockiert — wird in zukünftigen Runs ignoriert";

-- Reputation Tracking (akkumuliert über Research-Runs)
DEFINE FIELD correct_count ON source_registry TYPE int DEFAULT 0
  COMMENT "Wie oft haben Claims dieser Quelle Verification bestanden";
DEFINE FIELD incorrect_count ON source_registry TYPE int DEFAULT 0
  COMMENT "Wie oft haben Claims dieser Quelle Verification nicht bestanden";
DEFINE FIELD reputation_score ON source_registry TYPE float DEFAULT 0.5
  COMMENT "Laplace-smoothed: (correct+1)/(correct+incorrect+2)";

-- Metadata
DEFINE FIELD first_seen ON source_registry TYPE datetime;
DEFINE FIELD last_seen ON source_registry TYPE datetime;
DEFINE FIELD run_count ON source_registry TYPE int DEFAULT 0
  COMMENT "In wie vielen Runs wurde diese Quelle verwendet";
DEFINE FIELD tags ON source_registry TYPE array<string> DEFAULT []
  COMMENT "Domain-Tags für Filterung (z.B. AI, finance, travel)";
DEFINE FIELD notes ON source_registry TYPE option<string>
  COMMENT "Manuelle Notizen (via Portal)";

-- Indices
DEFINE INDEX idx_url ON source_registry FIELDS url UNIQUE;
DEFINE INDEX idx_domain ON source_registry FIELDS domain;
DEFINE INDEX idx_reputation ON source_registry FIELDS reputation_score;
DEFINE INDEX idx_trust ON source_registry FIELDS trust_level;
DEFINE INDEX idx_type ON source_registry FIELDS source_type;

-- ============================================================================
-- CREATOR REGISTRY — Kuratierte Content Creators (YouTube, X, Blogs, etc.)
-- ============================================================================

DEFINE TABLE creator SCHEMAFULL;

DEFINE FIELD name ON creator TYPE string;
DEFINE FIELD platform ON creator TYPE string
  ASSERT $value IN ["youtube", "x", "linkedin", "substack", "reddit", "blog", "rss", "podcast"]
  COMMENT "Primäre Plattform des Creators";
DEFINE FIELD channel_url ON creator TYPE string
  COMMENT "Haupt-URL (Channel, Profil, Blog)";

-- Platform-spezifische IDs
DEFINE FIELD rss_feed_url ON creator TYPE option<string>;
DEFINE FIELD youtube_channel_id ON creator TYPE option<string>;
DEFINE FIELD x_handle ON creator TYPE option<string>
  COMMENT "Ohne @ Prefix";

-- Trust + Kategorisierung
DEFINE FIELD trust_level ON creator TYPE string DEFAULT "watch"
  ASSERT $value IN ["high", "medium", "watch"]
  COMMENT "high=volle Vertrauenswürdigkeit, watch=unter Beobachtung";
DEFINE FIELD domain_tags ON creator TYPE array<string> DEFAULT []
  COMMENT "Themen-Tags z.B. [AI, finance, architecture]";

-- Status
DEFINE FIELD last_checked ON creator TYPE option<datetime>
  COMMENT "Wann wurde der Creator zuletzt auf neue Inhalte geprüft";
DEFINE FIELD active ON creator TYPE bool DEFAULT true
  COMMENT "Inaktive Creator werden beim Monitoring übersprungen";
DEFINE FIELD auto_discovered ON creator TYPE bool DEFAULT false
  COMMENT "true wenn vom Creator Discovery Agent vorgeschlagen";
DEFINE FIELD approved ON creator TYPE bool DEFAULT true
  COMMENT "false = wartet auf HITL-Approval (Auto-Discovery)";
DEFINE FIELD notes ON creator TYPE option<string>;

-- Indices
DEFINE INDEX idx_platform ON creator FIELDS platform;
DEFINE INDEX idx_trust ON creator FIELDS trust_level;
DEFINE INDEX idx_active ON creator FIELDS active;

-- ============================================================================
-- USED_SOURCE — Quellen-pro-Run Verknüpfung (Edge-Table)
-- ============================================================================

DEFINE TABLE used_source SCHEMAFULL;

DEFINE FIELD run ON used_source TYPE record<research_run>;
DEFINE FIELD source ON used_source TYPE record<source_registry>;
DEFINE FIELD relevance_score ON used_source TYPE float
  COMMENT "0.0-1.0, wie relevant war die Quelle für diesen Run";
DEFINE FIELD tier ON used_source TYPE string
  ASSERT $value IN ["T1", "T2", "T3"];
DEFINE FIELD gate_passed ON used_source TYPE bool
  COMMENT "Hat die Quelle Gate 1 (Credibility Scoring) bestanden?";
DEFINE FIELD gate_details ON used_source TYPE option<object>
  COMMENT "Detaillierte Gate-Ergebnisse (Scores pro Dimension)";
DEFINE FIELD extracted_claims ON used_source TYPE option<array>
  COMMENT "Aus dieser Quelle extrahierte Claims (Referenz)";

-- Indices
DEFINE INDEX idx_run ON used_source FIELDS run;
DEFINE INDEX idx_source ON used_source FIELDS source;

-- ============================================================================
-- RESEARCH_CLAIM — Claims pro Run (für Verification Table)
-- ============================================================================

DEFINE TABLE research_claim SCHEMAFULL;

DEFINE FIELD run_id ON research_claim TYPE record<research_run>;
DEFINE FIELD text ON research_claim TYPE string
  COMMENT "Die faktische Aussage";
DEFINE FIELD source_ids ON research_claim TYPE array<record<source_registry>> DEFAULT []
  COMMENT "Quellen die diesen Claim stützen";
DEFINE FIELD confidence ON research_claim TYPE float DEFAULT 0.0
  COMMENT "0.0-1.0 Gesamtconfidence nach allen Gates";

-- Verification-Ergebnisse
DEFINE FIELD cove_status ON research_claim TYPE option<string>
  ASSERT $value IN ["verified", "partially", "failed", none];
DEFINE FIELD factscore_status ON research_claim TYPE option<string>
  ASSERT $value IN ["SUPPORTED", "NOT_SUPPORTED", "AMBIGUOUS", none];
DEFINE FIELD judge_score ON research_claim TYPE option<float>
  COMMENT "LLM-as-Judge Score 0.0-5.0";
DEFINE FIELD final_status ON research_claim TYPE string DEFAULT "pending"
  ASSERT $value IN ["pending", "verified", "partially_verified", "refuted", "ambiguous"];

-- Counter-Research
DEFINE FIELD counter_evidence ON research_claim TYPE option<array>
  COMMENT "Gegenargumente aus Phase 2";
DEFINE FIELD devil_advocate_challenge ON research_claim TYPE option<string>
  COMMENT "Devil's Advocate Einwand";
DEFINE FIELD survived_adversarial ON research_claim TYPE option<bool>
  COMMENT "Hat den Red-Team-Challenge überlebt";

-- Index
DEFINE INDEX idx_run ON research_claim FIELDS run_id;
DEFINE INDEX idx_status ON research_claim FIELDS final_status;

-- ============================================================================
-- DIGEST_CHANNEL — Konfigurierbare Kanäle für Weekly Digest (Multi-Domain)
-- ============================================================================

DEFINE TABLE digest_channel SCHEMAFULL;

DEFINE FIELD name ON digest_channel TYPE string
  COMMENT "Kanalname z.B. 'Tech/AI', 'Finanzen', 'Branchen-News'";
DEFINE FIELD domain_tags ON digest_channel TYPE array<string> DEFAULT []
  COMMENT "Tags die MiniFlux-Entries und Creator-Content filtern";
DEFINE FIELD miniflux_category_ids ON digest_channel TYPE array<int> DEFAULT []
  COMMENT "MiniFlux Kategorie-IDs für diesen Kanal";
DEFINE FIELD active ON digest_channel TYPE bool DEFAULT true;
DEFINE FIELD schedule ON digest_channel TYPE string DEFAULT "0 8 * * 0"
  COMMENT "Cron-Expression (Default: Sonntag 08:00)";

-- ============================================================================
-- KB_SYNC — Edge-Table für Unified Source Model
-- Verlinkt verified Claims (≥T2) in openclaw/knowledge per Referenz
-- ============================================================================

DEFINE TABLE kb_sync SCHEMAFULL;

DEFINE FIELD claim_id ON kb_sync TYPE record<research_claim>;
DEFINE FIELD kb_namespace ON kb_sync TYPE string DEFAULT "openclaw/knowledge"
  COMMENT "Ziel-Namespace in openclaw/knowledge";
DEFINE FIELD kb_record_id ON kb_sync TYPE option<string>
  COMMENT "Record-ID im Ziel-Namespace (nach Sync gesetzt)";
DEFINE FIELD synced_at ON kb_sync TYPE option<datetime>;
DEFINE FIELD sync_status ON kb_sync TYPE string DEFAULT "pending"
  ASSERT $value IN ["pending", "synced", "failed"];

DEFINE INDEX idx_claim ON kb_sync FIELDS claim_id;
DEFINE INDEX idx_status ON kb_sync FIELDS sync_status;

-- ============================================================================
-- EVENTS — Automatische Reputation-Berechnung
-- ============================================================================

-- Wenn ein Claim verified wird, update die Source-Reputation
-- (In n8n als Code-Node implementiert, hier als Dokumentation)
--
-- Pseudocode:
--   FOR source IN claim.source_ids:
--     IF claim.final_status == "verified":
--       UPDATE source SET correct_count += 1
--     ELIF claim.final_status == "refuted":
--       UPDATE source SET incorrect_count += 1
--     UPDATE source SET reputation_score = (correct_count + 1) / (correct_count + incorrect_count + 2)
--
-- User-Feedback Loop:
--   IF report.user_rating == "thumbs_up":
--     FOR source IN run.sources: UPDATE source SET correct_count += 0.5
--   IF report.user_rating == "thumbs_down":
--     FOR source IN run.sources: UPDATE source SET incorrect_count += 0.5
--
-- Auto-Promotion:
--   IF source.reputation_score >= 0.80 AND source.run_count >= 5:
--     → Vorschlag zur Promotion auf T2 (HITL-Approval)

-- ============================================================================
-- SOURCE_RELIABILITY_EVENT — Append-only Audit Trail für Reputation-Mutationen
-- ============================================================================
-- Ersetzt die ursprünglich geplante "VERSION time::now()" Lösung
-- (verworfen weil VERSION clause CREATE+SELECT only, nicht UPDATE).
-- Jede Reputation-Änderung wird hier als separate immutable Row aufgezeichnet,
-- damit Drift über Zeit sichtbar wird ("wann wurde Source X unzuverlässig?").

DEFINE TABLE source_reliability_event SCHEMAFULL;

DEFINE FIELD source              ON source_reliability_event TYPE record<source_registry>;
DEFINE FIELD event_type          ON source_reliability_event TYPE string
  ASSERT $value IN ['correct', 'incorrect', 'manual_override', 'init']
  COMMENT "correct/incorrect = automatische Reputation-Update; manual_override = trust_level Promote/Downgrade; init = Erstanlage";
DEFINE FIELD old_score           ON source_reliability_event TYPE float;
DEFINE FIELD new_score           ON source_reliability_event TYPE float;
DEFINE FIELD delta               ON source_reliability_event TYPE float
  COMMENT "new_score - old_score (precomputed für GROUP BY queries)";
DEFINE FIELD trust_level_before  ON source_reliability_event TYPE option<string>;
DEFINE FIELD trust_level_after   ON source_reliability_event TYPE option<string>;
DEFINE FIELD claim_id            ON source_reliability_event TYPE option<record<research_claim>>
  COMMENT "Optional — current rate-based reputation hat keine claim-level Zuordnung";
DEFINE FIELD run_id              ON source_reliability_event TYPE option<record<research_run>>;
DEFINE FIELD created_at          ON source_reliability_event TYPE datetime DEFAULT time::now();

-- Zeitreihen-Query: "alle events für Source X, sortiert nach Zeit"
DEFINE INDEX idx_src_time ON source_reliability_event FIELDS source, created_at;
DEFINE INDEX idx_run      ON source_reliability_event FIELDS run_id;
DEFINE INDEX idx_created  ON source_reliability_event FIELDS created_at;

-- ============================================================================
-- RESEARCH_USER — Multi-User Identitaet (Nico + Sabine)
-- ============================================================================
-- Leichtgewichtige User-Tabelle fuer das Research-System.
-- Portal-Auth (Better Auth / Google OAuth) mappt per Email auf diese IDs.
-- Telegram Chat IDs fuer User-spezifische Benachrichtigungen.

DEFINE TABLE research_user SCHEMAFULL;

DEFINE FIELD email            ON research_user TYPE string;
DEFINE FIELD display_name     ON research_user TYPE string;
DEFINE FIELD telegram_chat_id ON research_user TYPE option<int>
  COMMENT "Telegram Chat ID fuer Benachrichtigungen";
DEFINE FIELD created_at       ON research_user TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_email ON research_user FIELDS email UNIQUE;

-- ============================================================================
-- USER_SOURCE_OVERRIDE — Per-User Trust-Ueberschreibungen
-- ============================================================================
-- Shared Global Pool + per-user overrides. Blockierte Quellen werden in
-- der Pipeline fuer diesen User uebersprungen. Gepinnte Quellen bekommen
-- hoehere Relevanz-Gewichtung.

DEFINE TABLE user_source_override SCHEMAFULL;

DEFINE FIELD user_id        ON user_source_override TYPE string
  COMMENT "research_user short ID (nico, sabine)";
DEFINE FIELD source         ON user_source_override TYPE record<source_registry>;
DEFINE FIELD trust_override ON user_source_override TYPE option<string>
  ASSERT $value IS NONE OR $value IN ["T1", "T2", "T3", "untrusted"]
  COMMENT "User-spezifische Trust-Level-Ueberschreibung";
DEFINE FIELD is_pinned      ON user_source_override TYPE bool DEFAULT false
  COMMENT "User hat diese Quelle als vertrauenswuerdig markiert";
DEFINE FIELD is_blocked     ON user_source_override TYPE bool DEFAULT false
  COMMENT "User hat diese Quelle blockiert — wird in Runs uebersprungen";
DEFINE FIELD notes          ON user_source_override TYPE option<string>;
DEFINE FIELD updated_at     ON user_source_override TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_user_source ON user_source_override FIELDS user_id, source UNIQUE;
DEFINE INDEX idx_user        ON user_source_override FIELDS user_id;

-- ============================================================================
-- USER_CREATOR_PREFERENCE — Per-User Creator Follow/Mute
-- ============================================================================

DEFINE TABLE user_creator_preference SCHEMAFULL;

DEFINE FIELD user_id    ON user_creator_preference TYPE string;
DEFINE FIELD creator    ON user_creator_preference TYPE record<creator>;
DEFINE FIELD following  ON user_creator_preference TYPE bool DEFAULT true;
DEFINE FIELD priority   ON user_creator_preference TYPE string DEFAULT "normal"
  ASSERT $value IN ["high", "normal", "muted"];
DEFINE FIELD updated_at ON user_creator_preference TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_user_creator ON user_creator_preference FIELDS user_id, creator UNIQUE;
DEFINE INDEX idx_user         ON user_creator_preference FIELDS user_id;

-- ============================================================================
-- MULTI-USER FIELD ADDITIONS (appended — never edit existing DEFINE FIELD)
-- ============================================================================

-- research_run: wer hat den Run ausgeloest
DEFINE FIELD user_id ON research_run TYPE option<string>
  COMMENT "research_user short ID (nico, sabine) oder NONE fuer System-Runs";
DEFINE INDEX idx_user ON research_run FIELDS user_id;

-- research_report: wer hat Feedback gegeben
DEFINE FIELD rating_user_id ON research_report TYPE option<string>
  COMMENT "Wer hat das Rating abgegeben (nico, sabine)";

-- trigger_source: erweitert um hive + openclaw_for_user
-- ACHTUNG: Dies ist ein absichtlicher DEFINE FIELD Override (Migration!)
DEFINE FIELD trigger_source ON research_run TYPE string
  ASSERT $value IN ["webhook", "schedule", "telegram", "manual", "portal", "openclaw", "hive", "openclaw_for_user"]
  COMMENT "Wie wurde der Run ausgeloest — openclaw_for_user = Agent handelt im Auftrag eines Users";
