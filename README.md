# GBAC E2E Test: Redpanda v26.1.1-rc4 BYOC Cluster

End-to-end test that provisions a Redpanda BYOC cluster on v26.1.1-rc4 and validates
Group-Based Access Control (GBAC) using the control plane IAM APIs.

## Overview

This test:
1. Provisions a BYOC cluster (AWS) pinned to Redpanda **v26.1.1-rc4** via Terraform
2. Creates a Kafka user and topic on the cluster
3. Exercises the GBAC control plane APIs (Roles, Groups, RoleBindings) via `curl`
4. Validates that role bindings can scope permissions to specific clusters and topics
5. Tears everything down

> **Note:** The Terraform provider does not yet have native resources for `redpanda_role`,
> `redpanda_group`, or `redpanda_role_binding`. GBAC configuration is done via the
> Redpanda Cloud public API (`/v1/roles`, `/v1/groups`, `/v1/role-bindings`).

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
    ├── main.tf                     # BYOC cluster + network + resource group
    ├── dataplane.tf                # User, topic, ACL resources
    ├── variables.tf                # Input variables
    ├── outputs.tf                  # Outputs (cluster ID, API URL, etc.)
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

## Step 3: Provision the BYOC Cluster

```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

**What this does:**

- `redpanda_resource_group` — creates an organizational container in Redpanda Cloud.
- `redpanda_network` — creates a BYOC-type network in `us-east-2` with CIDR `10.0.0.0/20`.
  The network defines the VPC that Redpanda will deploy into in your AWS account.
- `redpanda_cluster` — provisions the Redpanda cluster pinned to **v26.1.1-rc4**.
  Under the hood, the provider runs `rpk byoc apply` which deploys the Redpanda agent
  and cluster infrastructure into your AWS account. This step takes **30-45 minutes**.
- `redpanda_user` — creates a SCRAM-SHA-256 Kafka user on the cluster's dataplane.
- `redpanda_topic` — creates a 3-partition, RF=3 topic called `gbac-test-topic`.
- `redpanda_acl` (x2) — grants READ and WRITE on the topic to the Kafka user.

> **Note:** BYOC provisioning is slow because it bootstraps an EKS cluster, deploys
> the Redpanda agent, and waits for broker readiness. Monitor progress in the
> Redpanda Cloud Console.

---

## Step 4: Obtain a Bearer Token for API Calls

The GBAC APIs (`/v1/roles`, `/v1/groups`, `/v1/role-bindings`) are REST endpoints on
the Redpanda Cloud public API. They require a bearer token.

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

Set up common variables used in all subsequent API calls:

```bash
# Read the cluster ID from Terraform state — this is the 20-character XID
# that identifies the cluster in the control plane.
export CLUSTER_ID=$(cd terraform && terraform output -raw cluster_id)
export API_BASE="https://api.redpanda.com"

echo "CLUSTER_ID=${CLUSTER_ID}"
```

---

## Step 5: Create a Custom Role — "topic-admin"

Roles define a set of permissions. This role grants full topic lifecycle permissions
plus cluster read access. These are control-plane permissions that GBAC evaluates
when a user (or group member) performs actions.

```bash
curl -s -X POST "${API_BASE}/v1/roles" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "role": {
      "name": "gbac-test-topic-admin",
      "description": "Full topic lifecycle permissions for GBAC E2E test",
      "permissions": [
        "cluster_read",
        "topic_create",
        "topic_read",
        "topic_write",
        "topic_delete",
        "consumer_group_read"
      ]
    }
  }' | jq .
```

**Why:** We need a custom role (not a built-in one) to prove that the GBAC system
accepts user-defined permission sets. The `permissions` array uses the same permission
strings that the control plane checks via SpiceDB.

Save the role ID for later:

```bash
export ROLE1_ID=$(curl -s "${API_BASE}/v1/roles?filter.name=gbac-test-topic-admin" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.roles[0].id')
echo "ROLE1_ID=${ROLE1_ID}"
```

---

## Step 6: Create a Second Role — "readonly"

A narrower role to test that different permission sets can be bound independently.

```bash
curl -s -X POST "${API_BASE}/v1/roles" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "role": {
      "name": "gbac-test-readonly",
      "description": "Read-only permissions for GBAC E2E test",
      "permissions": [
        "cluster_read",
        "topic_read",
        "consumer_group_read"
      ]
    }
  }' | jq .
```

**Why:** Having two roles lets us verify that role bindings correctly associate
*different* permission sets to the same group at different scopes.

```bash
export ROLE2_ID=$(curl -s "${API_BASE}/v1/roles?filter.name=gbac-test-readonly" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.roles[0].id')
echo "ROLE2_ID=${ROLE2_ID}"
```

---

## Step 7: Create a Group

Groups are the "G" in GBAC. A group is an account entity (like a user or service account)
that can be assigned roles via role bindings. Members of the group inherit whatever
permissions the group has been granted.

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

**Why:** This creates the group as a first-class account in the IAM system
(`account_type = GROUP`). The group's ID can then be used as the `account_id`
in role bindings — the same field that accepts user or service account IDs.

```bash
export GROUP_ID=$(curl -s "${API_BASE}/v1/groups?filter.name=gbac-test-engineering" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.groups[0].id')
echo "GROUP_ID=${GROUP_ID}"
```

---

## Step 8: Create a Role Binding — Cluster-Scoped

A role binding connects a role to an account (user or group), optionally scoped
to a specific resource. This binding grants the `gbac-test-topic-admin` role to the
`gbac-test-engineering` group, scoped to our BYOC cluster.

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

**Why:** `resource_type: 3` = `SCOPE_RESOURCE_TYPE_CLUSTER`. This means the
topic-admin permissions only apply within this specific cluster — not org-wide.
This tests cluster-level scoping of GBAC permissions.

```bash
export RB1_ID=$(curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.role_bindings[0].id')
echo "RB1_ID=${RB1_ID}"
```

---

## Step 9: Create a Role Binding — Topic-Scoped

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

**Why:** `resource_type: 13` = `SCOPE_RESOURCE_TYPE_KAFKA_TOPIC`. Topic-level
scoping is a dataplane resource, so `dataplane_id` is required — it tells the
control plane which cluster owns the topic. The `resource_id` is the Kafka topic
name, not an XID. This tests the most granular GBAC scope.

```bash
export RB2_ID=$(curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq -r '.role_bindings[1].id')
echo "RB2_ID=${RB2_ID}"
```

---

## Step 10: Verify — Read Back All GBAC Resources

Now verify that every resource was persisted correctly by reading them back.

### Verify the topic-admin role

```bash
curl -s "${API_BASE}/v1/roles/${ROLE1_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

Expected: `name` = `gbac-test-topic-admin`, `is_builtin` = `false`, 6 permissions.

### Verify the readonly role

```bash
curl -s "${API_BASE}/v1/roles/${ROLE2_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

Expected: `name` = `gbac-test-readonly`, 3 permissions.

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
# Filter by account_ids to confirm both bindings are associated with the group.
curl -s "${API_BASE}/v1/role-bindings?filter.account_ids=${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}" | jq .
```

**Why:** This confirms the list endpoint's filter works and that both bindings
(cluster-scoped and topic-scoped) are returned for the group account.

---

## Step 11: Cleanup — Delete GBAC Resources

Delete in reverse dependency order: role bindings first (they reference roles and groups),
then the group, then the roles.

### Delete role bindings

```bash
# Delete the cluster-scoped binding
curl -s -X DELETE "${API_BASE}/v1/role-bindings/${RB1_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"

# Delete the topic-scoped binding
curl -s -X DELETE "${API_BASE}/v1/role-bindings/${RB2_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"
```

**Why:** Role bindings must be deleted before the roles or groups they reference.
If you delete a role while bindings still reference it, the binding becomes orphaned.

### Delete the group

```bash
curl -s -X DELETE "${API_BASE}/v1/groups/${GROUP_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"
```

**Why:** Deleting the group removes the account entity and cascades the deletion
of the underlying `account` row (the group table has `ON DELETE CASCADE`).

### Delete the roles

```bash
curl -s -X DELETE "${API_BASE}/v1/roles/${ROLE1_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"

curl -s -X DELETE "${API_BASE}/v1/roles/${ROLE2_ID}" \
  -H "Authorization: Bearer ${REDPANDA_TOKEN}"
```

---

## Step 12: Destroy Terraform Infrastructure

```bash
cd terraform/
terraform destroy -auto-approve
```

**What this does:**

- Deletes the ACLs, topic, and user from the cluster's dataplane.
- Runs `rpk byoc destroy` to tear down the BYOC agent and cluster infrastructure
  from your AWS account (EKS cluster, node groups, etc.).
- Deletes the network and resource group from Redpanda Cloud.

> **Note:** Destruction also takes 15-20 minutes as it drains and decommissions
> the BYOC infrastructure in AWS.

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
