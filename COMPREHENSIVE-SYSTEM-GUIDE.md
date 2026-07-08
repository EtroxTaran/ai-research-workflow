# Comprehensive System Guide: AI Research Workflow (n8n)

This document provides a complete, end-to-end overview of every aspect of the AI Research Workflow system. It details how the system is triggered, how it researches, iterates, validates, and finally presents the results.

---

## 1. How It Will Be Started (Triggers)
The system is highly accessible and can be triggered through multiple entry points:
*   **OpenClaw / Nathan (AI Assistant):** A user asks Nathan to "research X". Nathan uses the `research-workflow` skill to send a Webhook to n8n.
*   **Nexus Portal (Web UI):** Users can click "New Research" in the React-based web dashboard, which triggers the n8n Webhook.
*   **Scheduled Triggers (Cron):** 
    *   *Weekly Digest:* Runs every Sunday at 08:00 to aggregate news across configured domains.
    *   *Continuous Monitor:* Runs every 6 hours to find delta updates on tracked topics.
*   **Telegram Direct Message:** Users can message the dedicated "Research Bot" directly with a query.

---

## 2. How It Will Work (The Core Workflow)
The system follows a 5-Phase Orchestrator-Worker architecture:
*   **Phase 0 (Planning & Scoping):** An Orchestrator AI (Codex CLI) decomposes the user's query into sub-questions, identifies the domain (e.g., finance, tech), and determines the required depth mode (Quick, Standard, or Deep).
*   **Phase 1 (Parallel Gathering):** The system branches out, running 6-7 specialized search agents simultaneously to gather raw data from across the internet and internal databases.
*   **Phase 2 (Counter-Research):** A Devil's Advocate agent actively searches for evidence that contradicts the findings from Phase 1.
*   **Phase 3 (Verification):** Every extracted claim is rigorously fact-checked and scored.
*   **Phase 4 (Synthesis):** A final Synthesizer AI compiles the verified claims, the counter-arguments, and the sources into a highly structured Markdown report (Template v3).

---

## 3. How It Will Research & With Which Tools
Instead of relying on a single AI model, the system routes tasks to specialized tools and APIs:
*   **Web Search:** `Brave Search API` and `Tavily API` (for real-time web scraping and extraction).
*   **Deep Web Synthesis:** `Gemini CLI` with Google Search Grounding (replaces Perplexity for deep, cited web synthesis).
*   **Academic & Scientific:** `Semantic Scholar API` and `ArXiv API` (for peer-reviewed papers and preprints).
*   **Social Media & Real-Time Trends:** `Grok 4 API` with DeepSearch (for X/Twitter sentiment and breaking discussions).
*   **News & Blogs:** `MiniFlux RSS API` (for tracking trusted creators and publications).
*   **Internal Knowledge Base:** `SurrealDB` (Hybrid GraphRAG Search to check if we already know the answer).
*   **Optional Deep Search:** `You.com Research API` (used exclusively in "Deep" mode for maximum coverage).

---

## 4. How It Will Validate (Quality Gates)
The system employs 4 strict Quality Gates to prevent AI hallucinations and ensure academic-level rigor:
*   **Gate 1 (Source Sufficiency):** Checks if enough diverse sources were found. (e.g., Deep mode requires ≥12 sources across ≥3 platforms, with at least 5 being Tier 1/Tier 2 trusted sources).
*   **Gate 2 (Devil's Advocate):** Powered by `Claude 4.5 Opus`. It generates the 5 strongest counter-arguments for every claim, identifies confirmation bias, and runs a "Pre-Mortem" (imagining the research is wrong and explaining why).
*   **Gate 3 (Claim Verification):**
    *   *CoVe (Chain-of-Verification):* Checks claims for internal consistency.
    *   *FActScore:* Checks atomic claims against web search.
    *   *LLM-as-a-Judge:* A cross-model judge (Gemini evaluating Claude's output) scores the research 1-5 on Relevance, Accuracy, Completeness, Bias, and Actionability.
*   **Gate 4 (Structural Quality):** Ensures the final report complies with "Template v3" (must include a Verdict, Executive Summary, Contradictions, and cited Sources).

---

## 5. How It Will Iterate (The Replan Loop)
Research is rarely linear. If the system fails a Quality Gate (for example, if Gate 3 finds that 40% of the claims are unverified):
1.  The Orchestrator intercepts the failure.
2.  It identifies the "weak phase" (e.g., missing academic sources).
3.  It triggers a **Replan Loop**, generating new, highly specific sub-questions to fill the gap.
4.  The system iterates up to **3 times**. If it still fails after 3 retries, it escalates to a human.

---

## 6. How It Integrates Telegram & Human-in-the-Loop (HITL)
Telegram is the primary delivery and escalation mechanism, utilizing a dedicated **Research Bot**:
*   **Standard Delivery:** Once a report passes all gates, the Research Bot sends a Markdown summary and a link to the full report directly to the user's Telegram.
*   **Human-in-the-Loop (HITL) Escalation:** If the research involves a high-stakes domain (Finance, Medical), or if the final confidence score is below 75%, the bot sends an **Approval Request** via Telegram Inline Buttons.
    *   Buttons: `[✅ Approve]` `[❌ Reject]` `[✏️ Edit Query]`
    *   The system pauses and waits (up to 24 hours) for the user to click a button before saving the data to the Knowledge Base.
*   **Feedback Loop:** After reading a report, users can click `[👍 Hilfreich]` or `[👎 Nicht hilfreich]` in Telegram. This feedback updates the "Reputation Score" of the sources used in that specific run inside SurrealDB.

---

## 7. How It Will Present the Results
The final output is disseminated across multiple channels simultaneously:
*   **Telegram:** Executive summary and verdict delivered instantly.
*   **Google Drive:** The full Markdown report (and optionally a PDF) is uploaded to the shared `Familie/Research/` folder for archival.
*   **Nexus Portal:** The full report, along with interactive source credibility scores and the verification table, is viewable in the web dashboard.
*   **SurrealDB (Knowledge Base):** Only claims that *passed* verification are written back to the `openclaw/knowledge` database. Rejected sources are logged in an audit trail but never enter the active knowledge base.