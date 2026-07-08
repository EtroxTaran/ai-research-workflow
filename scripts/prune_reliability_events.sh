#!/usr/bin/env bash
# prune_reliability_events.sh
# Weekly prune of source_reliability_event rows older than the retention window.
# Default retention: 180d (configurable via RETENTION env, e.g. RETENTION=90d).
#
# Cron-friendly: outputs only on error or with --verbose.
# Schedule: weekly Sunday 04:00 -> "0 4 * * 0"

set -euo pipefail

SURREAL_URL="${SURREAL_URL:-http://localhost:8001/sql}"
SURREAL_NS="${SURREAL_NS:-research}"
SURREAL_DB="${SURREAL_DB:-workflow}"
SURREAL_USER="${SURREAL_USER:-root}"
SURREAL_PASS="${SURREAL_PASS:-openclaw2026}"
RETENTION="${RETENTION:-180d}"

VERBOSE=0
[[ "${1:-}" == "--verbose" ]] && VERBOSE=1

# Use RETURN BEFORE so we get the deleted rows back to count them
QUERY="DELETE source_reliability_event WHERE created_at < time::now() - ${RETENTION} RETURN BEFORE;"

response=$(curl -fsS -u "${SURREAL_USER}:${SURREAL_PASS}" \
  -X POST "${SURREAL_URL}" \
  -H "surreal-ns: ${SURREAL_NS}" \
  -H "surreal-db: ${SURREAL_DB}" \
  -H "Content-Type: text/plain" \
  -H "Accept: application/json" \
  --data-binary "${QUERY}")

# Parse status and count from response (stdlib python, no jq dependency)
deleted=$(python3 -c "
import json, sys
r = json.loads('''${response}''')
result = r[0].get('result') or []
print(len(result))
")

status=$(python3 -c "
import json, sys
r = json.loads('''${response}''')
print(r[0].get('status'))
")

if [[ "${status}" != "OK" ]]; then
  echo "ERROR: prune failed: ${response}" >&2
  exit 1
fi

if [[ ${VERBOSE} -eq 1 || ${deleted} -gt 0 ]]; then
  echo "$(date -Iseconds) prune_reliability_events: deleted=${deleted} retention=${RETENTION}"
fi
