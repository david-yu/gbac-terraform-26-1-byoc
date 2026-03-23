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
├── README.md                  # This file
├── terraform/
│   ├── provider.tf            # Provider configuration
│   ├── main.tf                # BYOC cluster + network + resource group
│   ├── dataplane.tf           # User, topic, ACL resources
│   ├── variables.tf           # Input variables
│   ├── outputs.tf             # Outputs (cluster ID, API URL, etc.)
│   └── terraform.tfvars.example
├── scripts/
│   ├── 01_setup_env.sh        # Set environment variables
│   ├── 02_gbac_create.sh      # Create roles, groups, role bindings
│   ├── 03_gbac_verify.sh      # Verify GBAC resources
│   └── 04_gbac_cleanup.sh     # Delete GBAC resources
└── test.sh                    # Full E2E orchestrator script
```

## Step-by-Step Instructions

### Step 1: Configure credentials

```bash
# Option A: OAuth client credentials (recommended)
export REDPANDA_CLIENT_ID="<your-client-id>"
export REDPANDA_CLIENT_SECRET="<your-client-secret>"

# Option B: Direct access token
export REDPANDA_ACCESS_TOKEN="<your-token>"

# AWS credentials for BYOC
export AWS_ACCESS_KEY_ID="<your-aws-key>"
export AWS_SECRET_ACCESS_KEY="<your-aws-secret>"
export AWS_DEFAULT_REGION="us-east-2"
```

### Step 2: Copy and edit tfvars

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired values
```

### Step 3: Provision the BYOC cluster

```bash
cd terraform/
terraform init
terraform plan
terraform apply -auto-approve
```

This will:
- Create a resource group
- Create a network (BYOC type)
- Provision the Redpanda cluster at **v26.1.1-rc4**
- Create a Kafka user, topic, and ACL

> **Note:** BYOC cluster provisioning can take 30-45 minutes.

### Step 4: Get an API token (if using client credentials)

```bash
# Fetch a bearer token from the Redpanda auth endpoint
export REDPANDA_TOKEN=$(curl -s -X POST "https://auth.prd.cloud.redpanda.com/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${REDPANDA_CLIENT_ID}" \
  -d "client_secret=${REDPANDA_CLIENT_SECRET}" \
  -d "audience=cloudv2-production.redpanda.cloud" | jq -r '.access_token')
```

Or if using a direct token:
```bash
export REDPANDA_TOKEN="${REDPANDA_ACCESS_TOKEN}"
```

### Step 5: Create GBAC resources (Roles, Groups, RoleBindings)

```bash
export CLUSTER_ID=$(cd terraform && terraform output -raw cluster_id)
export API_BASE="https://api.redpanda.com"

# Run the GBAC setup script
./scripts/02_gbac_create.sh
```

### Step 6: Verify GBAC resources

```bash
./scripts/03_gbac_verify.sh
```

### Step 7: Cleanup

```bash
# Delete GBAC resources first
./scripts/04_gbac_cleanup.sh

# Destroy Terraform-managed infrastructure
cd terraform/
terraform destroy -auto-approve
```

### Full automated run

```bash
./test.sh
```

## API Reference

### Roles API (`/v1/roles`)
- **POST** `/v1/roles` — Create a custom role with specific permissions
- **GET** `/v1/roles` — List all roles
- **GET** `/v1/roles/{id}` — Get a role
- **PATCH** `/v1/roles/{id}` — Update a role
- **DELETE** `/v1/roles/{id}` — Delete a role

### Groups API (`/v1/groups`)
- **POST** `/v1/groups` — Create a group
- **GET** `/v1/groups` — List all groups
- **GET** `/v1/groups/{id}` — Get a group
- **PATCH** `/v1/groups/{id}` — Update a group
- **DELETE** `/v1/groups/{id}` — Delete a group

### RoleBindings API (`/v1/role-bindings`)
- **POST** `/v1/role-bindings` — Bind a role to a user/group, optionally scoped to a resource
- **GET** `/v1/role-bindings` — List role bindings
- **GET** `/v1/role-bindings/{id}` — Get a role binding
- **DELETE** `/v1/role-bindings/{id}` — Delete a role binding

### RoleBinding Scope Resource Types
| Value | Type |
|-------|------|
| 1 | RESOURCE_GROUP |
| 2 | NETWORK |
| 3 | CLUSTER |
| 4 | SERVERLESS_CLUSTER |
| 6 | ORGANIZATION |
| 13 | KAFKA_TOPIC |

> For KAFKA_TOPIC scope, `dataplane_id` (the cluster ID) is required.
