#!/usr/bin/env bash
# Creates GBAC resources: Role, Group, and RoleBindings.
# Requires: REDPANDA_TOKEN, API_BASE, CLUSTER_ID
set -euo pipefail

: "${REDPANDA_TOKEN:?Set REDPANDA_TOKEN or source 01_setup_env.sh first}"
: "${API_BASE:?Set API_BASE (e.g. https://api.redpanda.com)}"
: "${CLUSTER_ID:?Set CLUSTER_ID from terraform output}"

AUTH="Authorization: Bearer ${REDPANDA_TOKEN}"
CT="Content-Type: application/json"

echo "========================================"
echo "  GBAC E2E: Creating GBAC Resources"
echo "========================================"

# ------------------------------------------------------------------
# 1. Create a custom Role with cluster + topic permissions
# ------------------------------------------------------------------
echo ""
echo "[1/5] Creating custom role: gbac-test-topic-admin"
ROLE_RESP=$(curl -sf -X POST "${API_BASE}/v1/roles" \
  -H "${AUTH}" -H "${CT}" \
  -d '{
    "role": {
      "name": "gbac-test-topic-admin",
      "description": "Test role for GBAC E2E - topic admin permissions",
      "permissions": [
        "cluster_read",
        "topic_create",
        "topic_read",
        "topic_write",
        "topic_delete",
        "consumer_group_read"
      ]
    }
  }')
ROLE_ID=$(echo "${ROLE_RESP}" | jq -r '.role.id')
ROLE_NAME=$(echo "${ROLE_RESP}" | jq -r '.role.name')
echo "  Role created: id=${ROLE_ID} name=${ROLE_NAME}"
echo "${ROLE_RESP}" | jq .

# ------------------------------------------------------------------
# 2. Create a second Role: read-only
# ------------------------------------------------------------------
echo ""
echo "[2/5] Creating custom role: gbac-test-readonly"
ROLE2_RESP=$(curl -sf -X POST "${API_BASE}/v1/roles" \
  -H "${AUTH}" -H "${CT}" \
  -d '{
    "role": {
      "name": "gbac-test-readonly",
      "description": "Test role for GBAC E2E - read only",
      "permissions": [
        "cluster_read",
        "topic_read",
        "consumer_group_read"
      ]
    }
  }')
ROLE2_ID=$(echo "${ROLE2_RESP}" | jq -r '.role.id')
ROLE2_NAME=$(echo "${ROLE2_RESP}" | jq -r '.role.name')
echo "  Role created: id=${ROLE2_ID} name=${ROLE2_NAME}"
echo "${ROLE2_RESP}" | jq .

# ------------------------------------------------------------------
# 3. Create a Group
# ------------------------------------------------------------------
echo ""
echo "[3/5] Creating group: gbac-test-engineering"
GROUP_RESP=$(curl -sf -X POST "${API_BASE}/v1/groups" \
  -H "${AUTH}" -H "${CT}" \
  -d '{
    "group": {
      "name": "gbac-test-engineering",
      "description": "Test group for GBAC E2E - engineering team"
    }
  }')
GROUP_ID=$(echo "${GROUP_RESP}" | jq -r '.group.id')
GROUP_NAME=$(echo "${GROUP_RESP}" | jq -r '.group.name')
echo "  Group created: id=${GROUP_ID} name=${GROUP_NAME}"
echo "${GROUP_RESP}" | jq .

# ------------------------------------------------------------------
# 4. Create RoleBinding: bind topic-admin role to group, scoped to cluster
# ------------------------------------------------------------------
echo ""
echo "[4/5] Creating role binding: gbac-test-topic-admin -> gbac-test-engineering (cluster-scoped)"
RB1_RESP=$(curl -sf -X POST "${API_BASE}/v1/role-bindings" \
  -H "${AUTH}" -H "${CT}" \
  -d "{
    \"role_binding\": {
      \"role_name\": \"${ROLE_NAME}\",
      \"account_id\": \"${GROUP_ID}\",
      \"scope\": {
        \"resource_type\": 3,
        \"resource_id\": \"${CLUSTER_ID}\"
      }
    }
  }")
RB1_ID=$(echo "${RB1_RESP}" | jq -r '.role_binding.id')
echo "  RoleBinding created: id=${RB1_ID}"
echo "${RB1_RESP}" | jq .

# ------------------------------------------------------------------
# 5. Create RoleBinding: bind readonly role to group, scoped to a specific topic
# ------------------------------------------------------------------
echo ""
echo "[5/5] Creating role binding: gbac-test-readonly -> gbac-test-engineering (topic-scoped)"
RB2_RESP=$(curl -sf -X POST "${API_BASE}/v1/role-bindings" \
  -H "${AUTH}" -H "${CT}" \
  -d "{
    \"role_binding\": {
      \"role_name\": \"${ROLE2_NAME}\",
      \"account_id\": \"${GROUP_ID}\",
      \"scope\": {
        \"resource_type\": 13,
        \"resource_id\": \"gbac-test-topic\",
        \"dataplane_id\": \"${CLUSTER_ID}\"
      }
    }
  }")
RB2_ID=$(echo "${RB2_RESP}" | jq -r '.role_binding.id')
echo "  RoleBinding created: id=${RB2_ID}"
echo "${RB2_RESP}" | jq .

# ------------------------------------------------------------------
# Save IDs for later scripts
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cat > "${SCRIPT_DIR}/.gbac_ids" <<EOF
ROLE_ID=${ROLE_ID}
ROLE_NAME=${ROLE_NAME}
ROLE2_ID=${ROLE2_ID}
ROLE2_NAME=${ROLE2_NAME}
GROUP_ID=${GROUP_ID}
GROUP_NAME=${GROUP_NAME}
RB1_ID=${RB1_ID}
RB2_ID=${RB2_ID}
EOF

echo ""
echo "========================================"
echo "  GBAC resources created successfully!"
echo "  IDs saved to scripts/.gbac_ids"
echo "========================================"
