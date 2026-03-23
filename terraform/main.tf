resource "redpanda_resource_group" "gbac_test" {
  name = var.resource_group_name
}

resource "redpanda_network" "gbac_test" {
  name              = var.network_name
  resource_group_id = redpanda_resource_group.gbac_test.id
  cloud_provider    = var.cloud_provider
  region            = var.region
  cluster_type      = "byoc"
  cidr_block        = var.cidr_block
}

resource "redpanda_cluster" "gbac_test" {
  name              = var.cluster_name
  resource_group_id = redpanda_resource_group.gbac_test.id
  network_id        = redpanda_network.gbac_test.id
  cloud_provider    = redpanda_network.gbac_test.cloud_provider
  region            = redpanda_network.gbac_test.region
  cluster_type      = redpanda_network.gbac_test.cluster_type
  connection_type   = "public"
  throughput_tier   = var.throughput_tier
  redpanda_version  = var.redpanda_version
  zones             = var.zones
  allow_deletion    = true

  tags = {
    "test"    = "gbac-e2e"
    "version" = var.redpanda_version
  }
}
