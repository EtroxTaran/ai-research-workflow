#!/usr/bin/env bash
# Enable MCP access (settings.availableInMCP) for all eligible workflows that are not yet enabled.
# Uses n8n internal REST API (same as Settings → MCP → Enable workflows).
#
# Requirements: curl, jq
#
# Usage:
#   export N8N_AUTH_COOKIE='n8n-auth=...'   # Application → Cookies (while logged in)
#   export N8N_BROWSER_ID='...'             # REQUIRED: same as UI — DevTools → Console: localStorage.getItem('n8n-browserId')
#                                           # (or Network → any /rest/* request → Request Headers → browser-id). Not the JWT "browserId" claim (that is a hash).
#   ./scripts/enable-n8n-mcp-workflows.sh --dry-run
#   ./scripts/enable-n8n-mcp-workflows.sh
#
# Environment:
#   N8N_BASE_URL       Base URL (default: http://127.0.0.1:5678)
#   N8N_AUTH_COOKIE    Full Cookie header value (preferred), e.g. n8n-auth=JWT...
#   N8N_SESSION_COOKIE Same as N8N_AUTH_COOKIE if the former is unset
#   N8N_BROWSER_ID     REQUIRED. n8n ties the session cookie to this header (see server.js: req.browserId = req.headers['browser-id']).
#   PAGE_SIZE          Page size for GET /mcp/workflows (default: 50)
#   N8N_REST_PREFIX    REST path prefix (default: /rest)

set -euo pipefail

DRY_RUN=false
while [[ $# -gt 0 ]]; do
	case "$1" in
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		grep -E '^#([^!]|$)' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
done

COOKIE="${N8N_AUTH_COOKIE:-${N8N_SESSION_COOKIE:-}}"
if [[ -z "${COOKIE}" ]]; then
	echo "error: set N8N_AUTH_COOKIE or N8N_SESSION_COOKIE to your logged-in session cookie." >&2
	exit 1
fi

BROWSER_ID="${N8N_BROWSER_ID:-}"
if [[ -z "${BROWSER_ID}" ]]; then
	echo "error: set N8N_BROWSER_ID to the same value the n8n UI sends on REST calls." >&2
	echo "  Easiest: DevTools → Console → localStorage.getItem('n8n-browserId')" >&2
	echo "  Or: Network → any .../rest/... request → Request Headers → browser-id (not the JWT payload field)." >&2
	exit 1
fi

BASE_URL="${N8N_BASE_URL:-http://127.0.0.1:5678}"
BASE_URL="${BASE_URL%/}"
REST_PREFIX="${N8N_REST_PREFIX:-/rest}"
REST_PREFIX="/${REST_PREFIX#/}"
PAGE_SIZE="${PAGE_SIZE:-50}"

list_url() {
	local skip=$1
	echo "${BASE_URL}${REST_PREFIX}/mcp/workflows?take=${PAGE_SIZE}&skip=${skip}"
}

toggle_url() {
	local id=$1
	echo "${BASE_URL}${REST_PREFIX}/mcp/workflows/${id}/toggle-access"
}

curl_get() {
	curl -sS \
		-H "Cookie: ${COOKIE}" \
		-H "browser-id: ${BROWSER_ID}" \
		-H "Accept: application/json" \
		-w "\n%{http_code}" \
		"$1"
}

curl_patch() {
	curl -sS \
		-X PATCH \
		-H "Cookie: ${COOKIE}" \
		-H "browser-id: ${BROWSER_ID}" \
		-H "Content-Type: application/json" \
		-H "Accept: application/json" \
		-d '{"availableInMCP":true}' \
		-w "\n%{http_code}" \
		"$1"
}

skip=0
total=0
failed=0

while true; do
	url=$(list_url "${skip}")
	resp=$(curl_get "${url}")
	http_code=$(echo "${resp}" | tail -n1)
	body=$(echo "${resp}" | sed '$d')

	if [[ "${http_code}" != "200" ]]; then
		echo "error: GET ${url} failed with HTTP ${http_code}" >&2
		echo "${body}" | head -c 500 >&2
		echo >&2
		if [[ "${http_code}" == "401" ]]; then
			echo "hint: cookie + N8N_BROWSER_ID must come from the same browser session (copy browser-id from a /rest/ request)." >&2
		fi
		exit 1
	fi

	len=$(echo "${body}" | jq '.data // [] | length')
	if [[ "${len}" -eq 0 ]]; then
		break
	fi

	while IFS=$'\t' read -r id name; do
		[[ -z "${id}" ]] && continue
		if [[ "${DRY_RUN}" == true ]]; then
			printf '[dry-run] would enable MCP: %s\t%s\n' "${id}" "${name}"
			total=$((total + 1))
			continue
		fi
		purl=$(toggle_url "${id}")
		presp=$(curl_patch "${purl}") || true
		pcode=$(echo "${presp}" | tail -n1)
		pbody=$(echo "${presp}" | sed '$d')
		if [[ "${pcode}" != "200" ]]; then
			echo "error: PATCH ${purl} failed HTTP ${pcode}" >&2
			echo "${pbody}" | head -c 400 >&2
			echo >&2
			failed=$((failed + 1))
		else
			printf 'enabled MCP: %s\t%s\n' "${id}" "${name}"
			total=$((total + 1))
		fi
	done < <(echo "${body}" | jq -r '.data[]? | [.id, (.name // "")] | @tsv')

	skip=$((skip + PAGE_SIZE))
done

if [[ "${DRY_RUN}" == true ]]; then
	echo "dry-run complete: ${total} workflow(s) would be updated."
else
	echo "done: ${total} workflow(s) patched; ${failed} error(s)."
	[[ "${failed}" -gt 0 ]] && exit 1
fi
