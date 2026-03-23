#!/usr/bin/env bash
# Deletes GBAC resources created by 02_gbac_create.sh.
# Requires: REDPANDA_TOKEN, API_BASE, and scripts/.gbac_ids
set -euo pipefail

: "${REDPANDA_TOKEN:?Set REDPANDA_TOKEN or source 01_setup_env.sh first}"
: "${API_BASE:?Set API_BASE (e.g. https://api.redpanda.com)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/.gbac_ids" ]]; then
  echo "ERROR: ${SCRIPT_DIR}/.gbac_ids not found. Nothing to clean up."
  exit 0
fi
source "${SCRIPT_DIR}/.gbac_ids"

AUTH="Authorization: Bearer ${REDPANDA_TOKEN}"

echo "========================================"
echo "  GBAC E2E: Cleaning Up GBAC Resources"
echo "========================================"

# Delete role bindings first (they reference roles and groups)
echo ""
echo "[1/4] Deleting role binding (cluster-scoped): ${RB1_ID}"
curl -sf -X DELETE "${API_BASE}/v1/role-bindings/${RB1_ID}" -H "${AUTH}" && echo "  Deleted" || echo "  Already gone or error"

echo ""
echo "[2/4] Deleting role binding (topic-scoped): ${RB2_ID}"
curl -sf -X DELETE "${API_BASE}/v1/role-bindings/${RB2_ID}" -H "${AUTH}" && echo "  Deleted" || echo "  Already gone or error"

# Delete group
echo ""
echo "[3/4] Deleting group: ${GROUP_ID}"
curl -sf -X DELETE "${API_BASE}/v1/groups/${GROUP_ID}" -H "${AUTH}" && echo "  Deleted" || echo "  Already gone or error"

# Delete roles
echo ""
echo "[4/4] Deleting roles: ${ROLE_ID}, ${ROLE2_ID}"
curl -sf -X DELETE "${API_BASE}/v1/roles/${ROLE_ID}" -H "${AUTH}" && echo "  Deleted role ${ROLE_ID}" || echo "  Already gone or error"
curl -sf -X DELETE "${API_BASE}/v1/roles/${ROLE2_ID}" -H "${AUTH}" && echo "  Deleted role ${ROLE2_ID}" || echo "  Already gone or error"

# Clean up state file
rm -f "${SCRIPT_DIR}/.gbac_ids"

echo ""
echo "========================================"
echo "  GBAC resources cleaned up."
echo "========================================"
