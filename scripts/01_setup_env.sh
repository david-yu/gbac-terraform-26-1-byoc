#!/usr/bin/env bash
# Sets up environment variables for GBAC testing.
# Source this file: source ./scripts/01_setup_env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../terraform"

# --- Redpanda API base ---
export API_BASE="${API_BASE:-https://api.redpanda.com}"

# --- Auth: get a bearer token ---
if [[ -n "${REDPANDA_ACCESS_TOKEN:-}" ]]; then
  export REDPANDA_TOKEN="${REDPANDA_ACCESS_TOKEN}"
  echo "[setup] Using REDPANDA_ACCESS_TOKEN"
elif [[ -n "${REDPANDA_CLIENT_ID:-}" && -n "${REDPANDA_CLIENT_SECRET:-}" ]]; then
  echo "[setup] Fetching token via client credentials..."
  REDPANDA_TOKEN=$(curl -sf -X POST "https://auth.prd.cloud.redpanda.com/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=${REDPANDA_CLIENT_ID}" \
    -d "client_secret=${REDPANDA_CLIENT_SECRET}" \
    -d "audience=cloudv2-production.redpanda.cloud" | jq -r '.access_token')
  export REDPANDA_TOKEN
  echo "[setup] Token acquired"
else
  echo "[setup] ERROR: Set REDPANDA_ACCESS_TOKEN or (REDPANDA_CLIENT_ID + REDPANDA_CLIENT_SECRET)"
  return 1 2>/dev/null || exit 1
fi

# --- Terraform outputs ---
if [[ -d "${TF_DIR}" ]] && terraform -chdir="${TF_DIR}" output -raw cluster_id &>/dev/null; then
  export CLUSTER_ID=$(terraform -chdir="${TF_DIR}" output -raw cluster_id)
  export CLUSTER_API_URL=$(terraform -chdir="${TF_DIR}" output -raw cluster_api_url)
  export RESOURCE_GROUP_ID=$(terraform -chdir="${TF_DIR}" output -raw resource_group_id)
  echo "[setup] CLUSTER_ID=${CLUSTER_ID}"
  echo "[setup] CLUSTER_API_URL=${CLUSTER_API_URL}"
  echo "[setup] RESOURCE_GROUP_ID=${RESOURCE_GROUP_ID}"
else
  echo "[setup] WARNING: Could not read Terraform outputs. Set CLUSTER_ID manually if needed."
fi

echo "[setup] Environment ready."
