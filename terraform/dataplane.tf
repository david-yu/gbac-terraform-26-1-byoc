resource "redpanda_user" "gbac_test" {
  name            = var.user_name
  password        = var.user_password
  mechanism       = "scram-sha-256"
  cluster_api_url = redpanda_cluster.gbac_test.cluster_api_url
}

resource "redpanda_topic" "gbac_test" {
  name               = var.topic_name
  partition_count     = var.partition_count
  replication_factor  = var.replication_factor
  cluster_api_url     = redpanda_cluster.gbac_test.cluster_api_url
  allow_deletion      = true
}

resource "redpanda_acl" "gbac_test_read" {
  resource_type         = "TOPIC"
  resource_name         = redpanda_topic.gbac_test.name
  resource_pattern_type = "LITERAL"
  principal             = "User:${redpanda_user.gbac_test.name}"
  host                  = "*"
  operation             = "READ"
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_cluster.gbac_test.cluster_api_url
}

resource "redpanda_acl" "gbac_test_write" {
  resource_type         = "TOPIC"
  resource_name         = redpanda_topic.gbac_test.name
  resource_pattern_type = "LITERAL"
  principal             = "User:${redpanda_user.gbac_test.name}"
  host                  = "*"
  operation             = "WRITE"
  permission_type       = "ALLOW"
  cluster_api_url       = redpanda_cluster.gbac_test.cluster_api_url
}
