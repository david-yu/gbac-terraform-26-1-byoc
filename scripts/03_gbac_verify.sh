#!/usr/bin/env bash
# Verifies GBAC resources exist and have correct configuration.
# Requires: REDPANDA_TOKEN, API_BASE, and scripts/.gbac_ids
set -euo pipefail

: "${REDPANDA_TOKEN:?Set REDPANDA_TOKEN or source 01_setup_env.sh first}"
: "${API_BASE:?Set API_BASE (e.g. https://api.redpanda.com)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/.gbac_ids" ]]; then
  echo "ERROR: ${SCRIPT_DIR}/.gbac_ids not found. Run 02_gbac_create.sh first."
  exit 1
fi
source "${SCRIPT_DIR}/.gbac_ids"

AUTH="Authorization: Bearer ${REDPANDA_TOKEN}"
PASS=0
FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "  PASS: ${label} = ${actual}"
    ((PASS++))
  else
    echo "  FAIL: ${label} expected='${expected}' actual='${actual}'"
    ((FAIL++))
  fi
}

echo "========================================"
echo "  GBAC E2E: Verifying GBAC Resources"
echo "========================================"

# ------------------------------------------------------------------
# 1. Verify Role: gbac-test-topic-admin
# ------------------------------------------------------------------
echo ""
echo "[1/5] Verifying role: ${ROLE_ID}"
ROLE=$(curl -sf -X GET "${API_BASE}/v1/roles/${ROLE_ID}" -H "${AUTH}")
check "role.name" "gbac-test-topic-admin" "$(echo "${ROLE}" | jq -r '.role.name')"
check "role.is_builtin" "false" "$(echo "${ROLE}" | jq -r '.role.is_builtin')"
PERM_COUNT=$(echo "${ROLE}" | jq -r '.role.permissions | length')
check "role.permissions count" "6" "${PERM_COUNT}"

# ------------------------------------------------------------------
# 2. Verify Role: gbac-test-readonly
# ------------------------------------------------------------------
echo ""
echo "[2/5] Verifying role: ${ROLE2_ID}"
ROLE2=$(curl -sf -X GET "${API_BASE}/v1/roles/${ROLE2_ID}" -H "${AUTH}")
check "role2.name" "gbac-test-readonly" "$(echo "${ROLE2}" | jq -r '.role.name')"
PERM2_COUNT=$(echo "${ROLE2}" | jq -r '.role.permissions | length')
check "role2.permissions count" "3" "${PERM2_COUNT}"

# ------------------------------------------------------------------
# 3. Verify Group
# ------------------------------------------------------------------
echo ""
echo "[3/5] Verifying group: ${GROUP_ID}"
GROUP=$(curl -sf -X GET "${API_BASE}/v1/groups/${GROUP_ID}" -H "${AUTH}")
check "group.name" "gbac-test-engineering" "$(echo "${GROUP}" | jq -r '.group.name')"

# ------------------------------------------------------------------
# 4. Verify RoleBinding: cluster-scoped
# ------------------------------------------------------------------
echo ""
echo "[4/5] Verifying role binding (cluster-scoped): ${RB1_ID}"
RB1=$(curl -sf -X GET "${API_BASE}/v1/role-bindings/${RB1_ID}" -H "${AUTH}")
check "rb1.role_name" "${ROLE_NAME}" "$(echo "${RB1}" | jq -r '.role_binding.role_name')"
check "rb1.account_id" "${GROUP_ID}" "$(echo "${RB1}" | jq -r '.role_binding.account_id')"
check "rb1.scope.resource_type" "SCOPE_RESOURCE_TYPE_CLUSTER" "$(echo "${RB1}" | jq -r '.role_binding.scope.resource_type')"

# ------------------------------------------------------------------
# 5. Verify RoleBinding: topic-scoped
# ------------------------------------------------------------------
echo ""
echo "[5/5] Verifying role binding (topic-scoped): ${RB2_ID}"
RB2=$(curl -sf -X GET "${API_BASE}/v1/role-bindings/${RB2_ID}" -H "${AUTH}")
check "rb2.role_name" "${ROLE2_NAME}" "$(echo "${RB2}" | jq -r '.role_binding.role_name')"
check "rb2.account_id" "${GROUP_ID}" "$(echo "${RB2}" | jq -r '.role_binding.account_id')"
check "rb2.scope.resource_type" "SCOPE_RESOURCE_TYPE_KAFKA_TOPIC" "$(echo "${RB2}" | jq -r '.role_binding.scope.resource_type')"
check "rb2.scope.resource_id" "gbac-test-topic" "$(echo "${RB2}" | jq -r '.role_binding.scope.resource_id')"

# ------------------------------------------------------------------
# 6. List role bindings filtered by group account
# ------------------------------------------------------------------
echo ""
echo "[bonus] Listing role bindings for group ${GROUP_ID}..."
RB_LIST=$(curl -sf -X GET "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" -H "${AUTH}")
RB_COUNT=$(echo "${RB_LIST}" | jq -r '.role_bindings | length')
echo "  Found ${RB_COUNT} role binding(s) for group"
check "role_bindings for group >= 2" "true" "$([ "${RB_COUNT}" -ge 2 ] && echo true || echo false)"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "========================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi
