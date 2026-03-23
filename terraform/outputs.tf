output "resource_group_id" {
  description = "ID of the Redpanda resource group"
  value       = redpanda_resource_group.gbac_test.id
}

output "network_id" {
  description = "ID of the Redpanda network"
  value       = redpanda_network.gbac_test.id
}

output "cluster_id" {
  description = "ID of the Redpanda BYOC cluster"
  value       = redpanda_cluster.gbac_test.id
}

output "cluster_api_url" {
  description = "Cluster API URL for dataplane operations"
  value       = redpanda_cluster.gbac_test.cluster_api_url
}

output "cluster_version" {
  description = "Redpanda version running on the cluster"
  value       = redpanda_cluster.gbac_test.redpanda_version
}

output "role_topic_admin" {
  description = "Name of the topic-admin role"
  value       = redpanda_role.topic_admin.name
}

output "role_readonly" {
  description = "Name of the readonly role"
  value       = redpanda_role.readonly.name
}
