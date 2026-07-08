# Research Workflow (n8n)

AI-Research Pipeline: n8n-Workflows mit Quality Gates, qualifiziertem Quellen-System und Nexus Portal UI.

## Wie es funktioniert

```
Nico → Nathan (OpenClaw Skill) → n8n Webhook → 7 Search-Branches parallel
                                                 → Verification Pipeline (CoVe + Judge)
                                                 → Research Bot (Telegram) + Portal
```

## Quick Facts
| | |
|---|---|
| **Plattform** | n8n Self-Hosted (Docker `n8n-local`, `localhost:5678` auf B-Link R2D2) |
| **Web UI** | Nexus Portal Plugin (`@nexus/plugin-research`) |
| **Datenbank** | SurrealDB v3 (`research/workflow` Namespace) |
| **Delivery** | Research Bot (Telegram) + Google Drive |
| **Phasen** | PRISMA → Recherche (7 Quellen) → Gegenrecherche → Verification → Synthese → Quality Gate |
| **Sprache** | Automatisch (DE/EN je nach Query) |

## Dokumente
| Datei | Inhalt |
|---|---|
| [PRODUCT-VISION.md](./PRODUCT-VISION.md) | Finalisierte Produktvision — Architektur, Phasen, Roadmap |
| [docs/n8n-workflow-specs.md](./docs/n8n-workflow-specs.md) | Technische Sub-Workflow-Spezifikationen |
| [schema/research-workflow.surql](./schema/research-workflow.surql) | SurrealDB Schema (direkt deploybar) |
| [portal/PLUGIN-SPEC.md](./portal/PLUGIN-SPEC.md) | Nexus Portal Plugin-Spezifikation |
| [docs/n8n-mcp-cursor-setup.md](./docs/n8n-mcp-cursor-setup.md) | Instance-level n8n MCP + Cursor (`mcp.json`, env, verification) |

## Roadmap
| Sprint | KW | Fokus |
|---|---|---|
| 1 | 15-16 | MVP: E2E Pipeline (KB + Web + MiniFlux → Synthese → Research Bot) |
| 2 | 16-17 | Verification + Portal Start + Perplexity |
| 3 | 17-18 | Full Stack (Academic + Social + YouTube + FActScore) |
| 4 | 18-19 | Spezial-Modi (Digest, Vergleiche) + Export |
| 5 | 19-20 | Optimierung + NotebookLM API |

## Status
🟡 PRODUCTION — Pipeline nativ auf R2D2, systemd Service, alle CLIs (Claude/Gemini/Codex) nativ. 22 aktive Workflows.
