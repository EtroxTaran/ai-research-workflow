# Verification Summary - Cursor MCP/Skills Setup

## n8n instance MCP (research-workflow-n8n)

1. Copy [env.n8n-mcp.example](./env.n8n-mcp.example) into `~/.openclaw/.env` (or export vars in the environment that **starts Cursor**).
2. Confirm [`.cursor/mcp.json`](./.cursor/mcp.json) contains the **`n8n`** server with `${env:N8N_MCP_URL}` and `${env:N8N_MCP_TOKEN}`.
3. Run `./scripts/verify-n8n-mcp.sh` (requires `curl` and reachable n8n). Expect **OK** for MCP initialize when Instance-level MCP is enabled and the token is valid.
4. Restart Cursor; **Output → MCP** should show **n8n** connected without errors.
5. Optional: `cd ~/projects/ai-portal && N8N_E2E_BASE_URL=http://localhost:5678 pnpm exec playwright test -c playwright.n8n.config.ts`

See [docs/n8n-mcp-cursor-setup.md](./docs/n8n-mcp-cursor-setup.md) for UI steps (enable Instance-level MCP, expose workflows) and LAN/Tailscale HTTP notes.

## Completed per Plan
- Git checkpoint created (commit d20233a).
- Synthesized Cursor v3 best practices (MCP project-level, skills with triggers/NOT-for/evals, rules in .mdc, shadcn+Playwright for UI, limit tools, env vars, HITL reinforcement).
- Audited current setup: context7, cursor-app-control MCPs active; research-workflow skill enhanced; global rules integrated; no package.json here (n8n-focused repo); ai-portal has Playwright CLI.
- Created:
  - `.cursor/mcp.json` (context7, cursor-app-control, playwright-mcp).
  - `.cursor/rules/00-research-workflow.mdc` (project constraints, n8n stability, MCP usage, skills integration).
  - `.cursor/rules/01-portal-ui.mdc` (shadcn, Playwright E2E, Zod from PLUGIN-SPEC).
  - Enhanced `skills/research-workflow/SKILL.md` (updated description, pipeline overview, Cursor integration, Nathan SOUL update).
- No changes to workflows/*.json, schema/, or production n8n (preserved stability).

## Next Steps for Full Functionality (ai-portal)
1. Switch workspace if needed: Use cursor-app-control MCP `move_agent_to_root` to `~/projects/ai-portal`.
2. In ai-portal:
   - `npx shadcn@latest init` (adds components.json, tailwind.config, etc. for research plugin).
   - Add shadcn components: `npx shadcn@latest add table card dialog tabs button form` for dashboard, SourceRegistryTable, NewResearchForm.
   - Update Playwright config/tests for research flows (use playwright-mcp for agent help).
   - `npm run lint`, `npx playwright test`, typecheck.
3. Test MCPs: Restart Cursor or reload window; check Output > MCP Logs. Verify context7 for docs on shadcn/Playwright/n8n.
4. Keys needed (if expanding MCPs or services):
   - Any new MCP auth (if not using npx stdio).
   - Confirm ~/.openclaw/.env has all (Brave, Tavily, Grok, You.com, Telegram Research Bot token).
   - For full playwright-mcp or other servers, may need additional setup.

## Tests/Lint
- This repo: No JS/TS — manual review via `git diff HEAD~1`.
- ai-portal: Run its scripts as noted.
- Skill test: Trigger "research React vs Svelte 2026" via OpenClaw/Nathan; verify n8n run starts without error.
- No impact on 22 active n8n workflows confirmed.

Setup now follows 2026 best practices for this research project. MCPs, skills, rules, and UI guidance are in place. Ready for shadcn/Playwright implementation in ai-portal or further tasks.

