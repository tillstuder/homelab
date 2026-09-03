provider "proxmox" {
  endpoint = var.pve_hosts[var.pve_node]
  insecure = var.pve_insecure
  min_tls  = "1.3"
}

provider "talos" {}

provider "cloudflare" {}
