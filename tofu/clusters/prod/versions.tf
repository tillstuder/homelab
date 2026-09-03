terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.24.0"
    }
  }
}
