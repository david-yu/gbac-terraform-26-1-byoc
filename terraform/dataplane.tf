locals {
  # RedpandaRole: prefix is used for ACLs bound to a role (not a user).
  # This lets Redpanda enforce ACLs for all members of the role at once.
  role_principal = "RedpandaRole:${redpanda_role.topic_admin.name}"
}

# --- Users ---

resource "redpanda_user" "gbac_test" {
  name            = var.user_name
  password        = var.user_password
  mechanism       = "scram-sha-256"
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url
}

# --- Topics ---

resource "redpanda_topic" "gbac_test" {
  name               = var.topic_name
  partition_count     = var.partition_count
  replication_factor  = var.replication_factor
  cluster_api_url     = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion      = true
}

# --- Roles (dataplane) ---

resource "redpanda_role" "topic_admin" {
  name            = "gbac-test-topic-admin"
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion  = true
}

resource "redpanda_role" "readonly" {
  name            = "gbac-test-readonly"
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion  = true
}

# --- Role Assignments (dataplane) ---

# Assign the topic-admin role to our Kafka user
resource "redpanda_role_assignment" "user_topic_admin" {
  role_name       = redpanda_role.topic_admin.name
  principal       = redpanda_user.gbac_test.name
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url

  depends_on = [redpanda_user.gbac_test]
}

# Assign the readonly role to the same user
resource "redpanda_role_assignment" "user_readonly" {
  role_name       = redpanda_role.readonly.name
  principal       = redpanda_user.gbac_test.name
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url

  depends_on = [redpanda_user.gbac_test]
}

# --- ACLs (bound to the role, not the user) ---

# Grant READ on the topic to the topic-admin role
resource "redpanda_acl" "role_topic_read" {
  resource_type         = "TOPIC"
  resource_name         = redpanda_topic.gbac_test.name
  resource_pattern_type = "LITERAL"
  principal             = local.role_principal
  host                  = "*"
  operation             = "READ"
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion        = true
}

# Grant WRITE on the topic to the topic-admin role
resource "redpanda_acl" "role_topic_write" {
  resource_type         = "TOPIC"
  resource_name         = redpanda_topic.gbac_test.name
  resource_pattern_type = "LITERAL"
  principal             = local.role_principal
  host                  = "*"
  operation             = "WRITE"
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion        = true
}

# Grant READ on consumer groups to the topic-admin role (needed for consuming)
resource "redpanda_acl" "role_group_read" {
  resource_type         = "GROUP"
  resource_name         = "*"
  resource_pattern_type = "LITERAL"
  principal             = local.role_principal
  host                  = "*"
  operation             = "READ"
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion        = true
}
