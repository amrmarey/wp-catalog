terraform {
  required_version = ">= 1.3.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0.0"
    }
  }
}

# Authentication:
#   Set environment variable CLOUDFLARE_API_TOKEN with a token that has
#   Zone:Read and DNS:Read permissions for the zones you want to query.
provider "cloudflare" {}


