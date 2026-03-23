terraform {
  required_version = ">= 1.6"

  required_providers {
    redpanda = {
      source  = "redpanda-data/redpanda"
      version = ">= 0.10.0"
    }
  }
}

# Authentication via environment variables:
#   REDPANDA_CLIENT_ID + REDPANDA_CLIENT_SECRET  (OAuth)
#   or REDPANDA_ACCESS_TOKEN                      (direct token)
provider "redpanda" {}
