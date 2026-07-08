#!/usr/bin/env bash
# Verify env and optional reachability of n8n instance MCP (Streamable HTTP).
# Usage: from repo root: ./scripts/verify-n8n-mcp.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail() {
  echo -e "${RED}FAIL:${NC} $*" >&2
  exit 1
}

ok() {
  echo -e "${GREEN}OK:${NC} $*"
}

warn() {
  echo -e "${YELLOW}WARN:${NC} $*"
}

if [[ -z "${N8N_MCP_URL:-}" ]]; then
  fail "N8N_MCP_URL is unset. Add it to ~/.openclaw/.env (see env.n8n-mcp.example) and export before starting Cursor."
fi

if [[ -z "${N8N_MCP_TOKEN:-}" ]]; then
  fail "N8N_MCP_TOKEN is unset. Copy token from n8n: Settings → Instance-level MCP → Connection details → Access Token."
fi

if [[ "${N8N_MCP_URL}" != *"/mcp-server/http"* ]]; then
  warn "N8N_MCP_URL should end with path /mcp-server/http (got: ${N8N_MCP_URL})"
fi

ok "N8N_MCP_URL and N8N_MCP_TOKEN are set."

# JSON-RPC initialize (MCP Streamable HTTP). Requires curl.
INIT_PAYLOAD='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"research-workflow-n8n-verify","version":"1.0.0"}}}'

HTTP_CODE=$(curl -sS -o /tmp/n8n-mcp-init-body.txt -w "%{http_code}" \
  -X POST "${N8N_MCP_URL}" \
  -H "Authorization: Bearer ${N8N_MCP_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  --connect-timeout 5 \
  --max-time 30 \
  -d "${INIT_PAYLOAD}" 2>/dev/null) || HTTP_CODE="000"

if [[ "${HTTP_CODE}" != "2"* ]]; then
  echo "Response body (first 500 chars):"
  head -c 500 /tmp/n8n-mcp-init-body.txt 2>/dev/null || true
  echo
  fail "MCP initialize failed (HTTP ${HTTP_CODE}). Check n8n is up, Instance-level MCP is enabled, token is valid, and URL matches your instance (same host as browser). See docs/n8n-mcp-cursor-setup.md."
fi

ok "MCP endpoint responded (HTTP ${HTTP_CODE}). Cursor should show n8n tools after reload if env is inherited."
rm -f /tmp/n8n-mcp-init-body.txt
exit 0
