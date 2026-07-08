# n8n instance-level MCP + Cursor

Operational runbook for this repo. For constraints and governance see [`.cursor/rules/00-research-workflow.mdc`](../.cursor/rules/00-research-workflow.mdc).

## Part A — n8n server and UI

1. **Version**: Use a current **n8n 2.x** build so **Settings → Instance-level MCP** exists ([docs](https://docs.n8n.io/advanced-ai/accessing-n8n-mcp-server/)).
2. **Do not disable MCP**: Ensure **`N8N_DISABLED_MODULES`** does **not** include `mcp` (that removes MCP endpoints and UI).
3. **Enable instance MCP**: As owner/admin: **Settings → Instance-level MCP → Enable MCP access**.
4. **Access token for Cursor**: **Connection details → Access Token** — copy the **MCP Access Token** when first shown (later visits are redacted).
5. **Expose workflows**: No workflows are visible to MCP until enabled. Use **Available in MCP** per workflow (workflow **…** → **Settings**) or **Instance-level MCP → Enable workflows**.  
   **Governance**: The production orchestrator (`69QGdrWQneaaph5Z`, etc.) should only be exposed after explicit approval; prefer safe or dev workflows first.  
   **Bulk enable (eligible workflows only):** [scripts/enable-n8n-mcp-workflows.sh](../scripts/enable-n8n-mcp-workflows.sh) uses the same REST surface as the UI (`N8N_AUTH_COOKIE`, **`N8N_BROWSER_ID`** required — see script header and [NEXT-SESSION.md](../NEXT-SESSION.md)).

## Part B — Cursor (`mcp.json`)

Project config: [`.cursor/mcp.json`](../.cursor/mcp.json) includes an **`n8n`** HTTP MCP server:

- `url`: `${env:N8N_MCP_URL}` — must end with `/mcp-server/http`
- `headers.Authorization`: `Bearer ${env:N8N_MCP_TOKEN}`

Restart Cursor after changing env or `mcp.json`. Check **Output → MCP** for connection errors.

## Environment variables

Copy [../env.n8n-mcp.example](../env.n8n-mcp.example) lines into `~/.openclaw/.env` (or any file you source before starting Cursor). Cursor must inherit **`N8N_MCP_URL`** and **`N8N_MCP_TOKEN`** so `${env:…}` resolves.

Examples:

- Same host as n8n: `N8N_MCP_URL=http://localhost:5678/mcp-server/http`
- Remote / Tailscale / LAN: use the **same origin** you use in the browser, e.g. `http://r2d2.tailXXXX.ts.net:5678/mcp-server/http` or `https://…/mcp-server/http` if TLS in front.

## Part E — HTTP on LAN / Tailscale (login + cookies)

If you use **`http://`** with a **non-localhost** hostname, set on the **n8n host** (see [NEXT-SESSION.md](../NEXT-SESSION.md)):

- `N8N_EDITOR_BASE_URL` matching the browser URL
- `N8N_SECURE_COOKIE=false` for plain HTTP on trusted networks, **or** terminate **HTTPS** (Tailscale Serve, Caddy, nginx) and use `N8N_PROTOCOL=https` + default secure cookies.

Confirm variables reach the n8n process (systemd `EnvironmentFile`, then `daemon-reload` + restart).

## Verification

Run from this repo:

```bash
./scripts/verify-n8n-mcp.sh
```

Optional UI smoke (requires Playwright and env): see [Optional Playwright n8n smoke](#optional-playwright-n8n-smoke) below.

## Optional Playwright n8n smoke

In **`ai-portal`** (sibling repo), optional tests are isolated so default `pnpm test:e2e` does not require n8n:

```bash
cd ~/projects/ai-portal
N8N_E2E_BASE_URL=http://localhost:5678 pnpm exec playwright test -c playwright.n8n.config.ts
```

Set **`N8N_E2E_BASE_URL`** to a reachable n8n origin. Tests are skipped if unset when using the dedicated config.
