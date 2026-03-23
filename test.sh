#!/usr/bin/env bash
# Full E2E orchestrator: provision BYOC cluster, test GBAC, tear down.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"

echo "============================================================"
echo "  GBAC E2E Test: Redpanda v26.1.1-rc4 BYOC + GBAC"
echo "============================================================"
echo ""

# ------------------------------------------------------------------
# Phase 1: Terraform apply
# ------------------------------------------------------------------
echo ">>> Phase 1: Provisioning BYOC cluster via Terraform"
echo ""
cd "${TF_DIR}"
terraform init -input=false
terraform apply -auto-approve -input=false
echo ""
echo ">>> Cluster provisioned. Waiting 30s for dataplane readiness..."
sleep 30

# ------------------------------------------------------------------
# Phase 2: Setup env
# ------------------------------------------------------------------
echo ""
echo ">>> Phase 2: Setting up environment"
cd "${SCRIPT_DIR}"
source ./scripts/01_setup_env.sh

# ------------------------------------------------------------------
# Phase 3: Create GBAC resources
# ------------------------------------------------------------------
echo ""
echo ">>> Phase 3: Creating GBAC resources (Roles, Groups, RoleBindings)"
bash ./scripts/02_gbac_create.sh

# ------------------------------------------------------------------
# Phase 4: Verify GBAC resources
# ------------------------------------------------------------------
echo ""
echo ">>> Phase 4: Verifying GBAC resources"
bash ./scripts/03_gbac_verify.sh
VERIFY_EXIT=$?

# ------------------------------------------------------------------
# Phase 5: Cleanup GBAC
# ------------------------------------------------------------------
echo ""
echo ">>> Phase 5: Cleaning up GBAC resources"
bash ./scripts/04_gbac_cleanup.sh

# ------------------------------------------------------------------
# Phase 6: Terraform destroy
# ------------------------------------------------------------------
echo ""
echo ">>> Phase 6: Destroying Terraform infrastructure"
cd "${TF_DIR}"
terraform destroy -auto-approve -input=false

# ------------------------------------------------------------------
# Final result
# ------------------------------------------------------------------
echo ""
echo "============================================================"
if [[ ${VERIFY_EXIT} -eq 0 ]]; then
  echo "  E2E TEST PASSED"
else
  echo "  E2E TEST FAILED (verification step)"
fi
echo "============================================================"
exit ${VERIFY_EXIT}
