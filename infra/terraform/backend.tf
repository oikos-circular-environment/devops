terraform {
  required_version = ">= 1.15.0"

  cloud {
    organization = "oikos-circular-economy"

    workspaces {
      name = "oracle-server"
    }
  }

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.0.0, < 9.0.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.0.0, < 6.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0, < 5.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.0, < 1.0.0"
    }
  }
}
