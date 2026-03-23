variable "resource_group_name" {
  description = "Name of the Redpanda resource group"
  type        = string
  default     = "gbac-test-rg"
}

variable "network_name" {
  description = "Name of the Redpanda network"
  type        = string
  default     = "gbac-test-network"
}

variable "cluster_name" {
  description = "Name of the Redpanda BYOC cluster"
  type        = string
  default     = "gbac-test-cluster"
}

variable "cloud_provider" {
  description = "Cloud provider (aws, gcp, azure)"
  type        = string
  default     = "aws"
}

variable "region" {
  description = "Cloud region for the cluster"
  type        = string
  default     = "us-east-2"
}

variable "zones" {
  description = "Availability zones for the cluster"
  type        = list(string)
  default     = ["use2-az1", "use2-az2", "use2-az3"]
}

variable "throughput_tier" {
  description = "Throughput tier for the cluster"
  type        = string
  default     = "tier-1-aws-v2-x86"
}

variable "redpanda_version" {
  description = "Redpanda version to deploy"
  type        = string
  default     = "v26.1.1-rc4"
}

variable "cidr_block" {
  description = "CIDR block for the network"
  type        = string
  default     = "10.0.0.0/20"
}

# Dataplane variables

variable "user_name" {
  description = "Kafka user name"
  type        = string
  default     = "gbac-test-user"
}

variable "user_password" {
  description = "Kafka user password"
  type        = string
  sensitive   = true
  default     = "Chang3Me!Secur3"
}

variable "topic_name" {
  description = "Kafka topic name"
  type        = string
  default     = "gbac-test-topic"
}

variable "partition_count" {
  description = "Number of topic partitions"
  type        = number
  default     = 3
}

variable "replication_factor" {
  description = "Topic replication factor"
  type        = number
  default     = 3
}
