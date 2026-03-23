# GBAC E2E Test: Redpanda v26.1.1-rc4 BYOC Cluster

End-to-end test that provisions a Redpanda BYOC cluster on v26.1.1-rc4 and validates
Group-Based Access Control (GBAC) using both the Terraform provider and the control
plane IAM APIs.

## What is tested

| Layer | Resource | Managed via | Why |
|-------|----------|-------------|-----|
| Dataplane | Roles (`redpanda_role`) | Terraform | Creates named roles on the cluster's Kafka-level RBAC system |
| Dataplane | Role assignments (`redpanda_role_assignment`) | Terraform | Assigns roles to Kafka principals (users) on the cluster |
| Dataplane | ACLs (`redpanda_acl`) | Terraform | Binds permissions to roles using `RedpandaRole:` principal prefix |
| Control plane | Groups | `curl` | No `redpanda_group` TF resource exists yet |
| Control plane | Role bindings | `curl` | No `redpanda_role_binding` TF resource exists yet — binds control plane roles to groups with resource scoping |

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured with credentials for the BYOC target account
- Redpanda Cloud credentials (client ID + secret, or access token)
- `curl` and `jq` installed
- `rpk` installed (the Terraform provider invokes `rpk byoc` under the hood)

## Directory Structure

```
.
├── README.md                       # This file (all commands + explanations)
└── terraform/
    ├── provider.tf                 # Provider configuration
    ├── main.tf                     # Resource group, network, BYOC cluster
    ├── dataplane.tf                # User, topic, roles, role assignments, ACLs
    ├── variables.tf                # Input variables
    ├── outputs.tf                  # Outputs (cluster ID, API URL, role names)
    └── terraform.tfvars.example
```

---

## Step 1: Configure Credentials

The Terraform provider and the GBAC API calls both need authentication. The provider
reads credentials from environment variables automatically.

```bash
# --- Redpanda Cloud auth ---
# Option A: OAuth client credentials (recommended for CI/automation)
export REDPANDA_CLIENT_ID="<your-client-id>"
export REDPANDA_CLIENT_SECRET="<your-client-secret>"

# Option B: Direct access token (e.g. from the Redpanda Console)
export REDPANDA_ACCESS_TOKEN="<your-token>"

# --- AWS credentials for BYOC ---
# The provider runs `rpk byoc apply` which provisions infrastructure in YOUR
# AWS account. Standard AWS credentials must be available.
export AWS_ACCESS_KEY_ID="<your-aws-key>"
export AWS_SECRET_ACCESS_KEY="<your-aws-secret>"
export AWS_DEFAULT_REGION="us-east-2"
```

---

## Step 2: Copy and Edit tfvars

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to set your desired cluster name, region, zones, etc.
The defaults target AWS `us-east-2` with 3 AZs.

---

## Step 3: Provision the BYOC Cluster, Roles, and Role Assignments

```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

**What this creates (in dependency order):**

1. `redpanda_resource_group` — organizational container in Redpanda Cloud.
2. `redpanda_network` — BYOC-type network in `us-east-2` with CIDR `10.0.0.0/20`.
   Defines the VPC that Redpanda will deploy into in your AWS account.
3. `redpanda_cluster` — the Redpanda cluster pinned to **v26.1.1-rc4** via the
   `redpanda_version` attribute. Under the hood, the provider runs `rpk byoc apply`
   which deploys the Redpanda agent and cluster infrastructure into AWS.
   **This step takes 30-45 minutes.**
4. `redpanda_user` — a SCRAM-SHA-256 Kafka user (`gbac-test-user`) on the cluster
   dataplane. This user will be assigned to roles.
5. `redpanda_topic` — a 3-partition, RF=3 topic (`gbac-test-topic`).
6. `redpanda_role` (x2) — creates two **dataplane roles** on the cluster:
   - `gbac-test-topic-admin` — will get read/write/consumer-group ACLs
   - `gbac-test-readonly` — a second role for testing multiple assignments

   These are Kafka-level RBAC roles, managed through the cluster's SecurityService
   gRPC API. They exist on the cluster itself, not in the control plane.
7. `redpanda_role_assignment` (x2) — assigns both roles to `gbac-test-user`.
   The assignment uses `UpdateRoleMembership` on the dataplane — the user becomes
   a member of each role and inherits whatever ACLs are bound to that role.
8. `redpanda_acl` (x3) — binds permissions to the `gbac-test-topic-admin` role
   using the `RedpandaRole:gbac-test-topic-admin` principal:
   - TOPIC READ on `gbac-test-topic`
   - TOPIC WRITE on `gbac-test-topic`
   - GROUP READ on `*` (needed for consumer group access)

   Any user assigned to `gbac-test-topic-admin` inherits these ACLs automatically.

---

## Step 4: Obtain a Bearer Token for Control Plane API Calls

The control plane Group and RoleBinding APIs (`/v1/groups`, `/v1/role-bindings`) are
REST endpoints that require a bearer token. This is separate from the dataplane auth
that Terraform handles automatically.

**If using OAuth client credentials:**

```bash
# Exchange client credentials for a short-lived JWT.
# The audience must match the Redpanda Cloud production environment.
export REDPANDA_TOKEN=$(curl -s -X POST "https://auth.prd.cloud.redpanda.com/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${REDPANDA_CLIENT_ID}" \
  -d "client_secret=${REDPANDA_CLIENT_SECRET}" \
  -d "audience=cloudv2-production.redpanda.cloud" | jq -r '.access_token')

echo "Token acquired (first 20 chars): ${REDPANDA_TOKEN:0:20}..."
```

**If using a direct access token:**

```bash
export REDPANDA_TOKEN="${REDPANDA_ACCESS_TOKEN}"
```

Set up common variables for the remaining API calls:

```bash
# Read the cluster ID from Terraform state — this is the 20-character XID
# that identifies the cluster in the control plane.
export CLUSTER_ID=$(cd terraform && terraform output -raw cluster_id)
export API_BASE="https://api.redpanda.com"

echo "CLUSTER_ID=${CLUSTER_ID}"
```

---

## Step 5: Create a Control Plane Group

Groups are the "G" in GBAC. A group is an account entity (like a user or service account)
that can be assigned control plane roles via role bindings. Members of the group inherit
whatever permissions the group has been granted.

There is no `redpanda_group` Terraform resource yet, so we use the REST API directly.

```bash
curl -s -X POST "${API_BASE}/v1/groups" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "group": {
      "name": "gbac-test-engineering",
      "description": "Engineering team group for GBAC E2E test"
    }
  }' | jq .
```

**Why:** The `POST /v1/groups` endpoint creates the group as a first-class account
in the control plane IAM system (`account_type = GROUP` in the `account` table).
The group's 20-character XID can then be used as the `account_id` in role bindings —
the same field that accepts user or service account IDs.

Save the group ID:

```bash
export GROUP_ID=$(curl -s "${API_BASE}/v1/groups?filter.name=gbac-test-engineering" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.groups[0].id')
echo "GROUP_ID=${GROUP_ID}"
```

---

## Step 6: Create a Control Plane Role Binding — Cluster-Scoped

A role binding connects a control plane role to an account (user or group), optionally
scoped to a specific resource. This binding grants permissions to the
`gbac-test-engineering` group, scoped to our BYOC cluster.

There is no `redpanda_role_binding` Terraform resource yet, so we use the REST API.

```bash
curl -s -X POST "${API_BASE}/v1/role-bindings" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"role_binding\": {
      \"role_name\": \"gbac-test-topic-admin\",
      \"account_id\": \"${GROUP_ID}\",
      \"scope\": {
        \"resource_type\": 3,
        \"resource_id\": \"${CLUSTER_ID}\"
      }
    }
  }" | jq .
```

**Why:** `resource_type: 3` = `SCOPE_RESOURCE_TYPE_CLUSTER`. This scopes the binding
so that the group's permissions only apply within this specific cluster — not org-wide.
The `role_name` references `gbac-test-topic-admin` which we already created as a
dataplane role in Step 3. The `account_id` is the group's XID, linking the role to the
group rather than an individual user.

Save the role binding ID:

```bash
export RB1_ID=$(curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.role_bindings[0].id')
echo "RB1_ID=${RB1_ID}"
```

---

## Step 7: Create a Control Plane Role Binding — Topic-Scoped

This binding grants the `gbac-test-readonly` role to the same group, but scoped
to a **specific Kafka topic** on the cluster.

```bash
curl -s -X POST "${API_BASE}/v1/role-bindings" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"role_binding\": {
      \"role_name\": \"gbac-test-readonly\",
      \"account_id\": \"${GROUP_ID}\",
      \"scope\": {
        \"resource_type\": 13,
        \"resource_id\": \"gbac-test-topic\",
        \"dataplane_id\": \"${CLUSTER_ID}\"
      }
    }
  }" | jq .
```

**Why:** `resource_type: 13` = `SCOPE_RESOURCE_TYPE_KAFKA_TOPIC`. This is the most
granular scope available. Because topics are dataplane resources (they don't have
globally unique IDs), the `dataplane_id` field is **required** — it tells the control
plane which cluster owns the topic. The `resource_id` is the Kafka topic name
(`gbac-test-topic`), not an XID.

This tests that GBAC can restrict a group's permissions down to a single topic on
a single cluster.

Save the role binding ID:

```bash
export RB2_ID=$(curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.role_bindings[1].id')
echo "RB2_ID=${RB2_ID}"
```

---

## Step 8: Verify All Resources

### Verify Terraform-managed resources

```bash
cd terraform/

# Confirm the cluster is running v26.1.1-rc4
terraform output cluster_version

# Confirm the role names
terraform output role_topic_admin
terraform output role_readonly

# Full state check — Terraform will read back each resource from the API
# and flag any drift
terraform plan
```

**Why:** `terraform plan` on an already-applied config should show "No changes."
If it doesn't, it means the cluster or dataplane resources have drifted from the
declared state — which would be a provider bug worth investigating.

### Verify the group

```bash
curl -s "${API_BASE}/v1/groups/${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

Expected: `name` = `gbac-test-engineering`.

### Verify the cluster-scoped role binding

```bash
curl -s "${API_BASE}/v1/role-bindings/${RB1_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

Expected: `role_name` = `gbac-test-topic-admin`, `account_id` = the group ID,
`scope.resource_type` = `SCOPE_RESOURCE_TYPE_CLUSTER`.

### Verify the topic-scoped role binding

```bash
curl -s "${API_BASE}/v1/role-bindings/${RB2_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

Expected: `role_name` = `gbac-test-readonly`, `scope.resource_type` = `SCOPE_RESOURCE_TYPE_KAFKA_TOPIC`,
`scope.resource_id` = `gbac-test-topic`, `scope.dataplane_id` = the cluster ID.

### List all role bindings for the group

```bash
curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

**Why:** Confirms the list endpoint filter works and that both bindings (cluster-scoped
and topic-scoped) are returned for the group account.

---

## Step 9: Cleanup

Delete in reverse dependency order: control plane role bindings first, then the group,
then let Terraform handle the rest.

### Delete control plane role bindings

```bash
# Delete the cluster-scoped binding
curl -s -X DELETE "${API_BASE}/v1/role-bindings/${RB1_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"

# Delete the topic-scoped binding
curl -s -X DELETE "${API_BASE}/v1/role-bindings/${RB2_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"
```

**Why:** Role bindings must be deleted before the group they reference. If you
delete the group first, the bindings become orphaned and may fail to delete cleanly.

### Delete the group

```bash
curl -s -X DELETE "${API_BASE}/v1/groups/${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"
```

**Why:** Deleting the group removes the account entity. The underlying `account`
row cascades (`ON DELETE CASCADE`), cleaning up related IAM state in the control plane.

### Destroy Terraform-managed infrastructure

```bash
cd terraform/
terraform destroy -auto-approve
```

**What this tears down (in reverse dependency order):**

- ACLs (role-bound topic read/write, consumer group read)
- Role assignments (user removed from both roles)
- Roles (`gbac-test-topic-admin`, `gbac-test-readonly`)
- Topic and user
- Cluster — runs `rpk byoc destroy` to tear down the EKS cluster, node groups,
  and all BYOC infrastructure from your AWS account (**takes 15-20 minutes**)
- Network and resource group

---

## Appendix: RoleBinding Scope Resource Types

| `resource_type` value | Enum name | Description |
|---|---|---|
| 1 | `SCOPE_RESOURCE_TYPE_RESOURCE_GROUP` | Scoped to a resource group |
| 2 | `SCOPE_RESOURCE_TYPE_NETWORK` | Scoped to a network |
| 3 | `SCOPE_RESOURCE_TYPE_CLUSTER` | Scoped to a dedicated/BYOC cluster |
| 4 | `SCOPE_RESOURCE_TYPE_SERVERLESS_CLUSTER` | Scoped to a serverless cluster |
| 6 | `SCOPE_RESOURCE_TYPE_ORGANIZATION` | Org-wide (broadest scope) |
| 13 | `SCOPE_RESOURCE_TYPE_KAFKA_TOPIC` | Scoped to a specific Kafka topic (requires `dataplane_id`) |

> For all dataplane resources (types 7-13), `dataplane_id` must be set to the
> cluster or serverless cluster ID that owns the resource.
