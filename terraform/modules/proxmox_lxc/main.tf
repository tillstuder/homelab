# Original Source: https://github.com/TechDufus/home.io/blob/main/terraform/proxmox/modules/proxmox_lxc/main.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

resource "proxmox_lxc" "lxc_container" {
  vmid         = var.vmid
  hostname     = var.hostname
  description  = var.description
  cores        = var.cores
  memory       = var.memory
  swap         = var.swap
  onboot       = var.onboot
  unprivileged = var.unprivileged
  start        = var.start
  tags         = var.tags

  target_node     = var.target_node
  ostemplate      = var.ostemplate
  ssh_public_keys = var.ssh_public_keys

  rootfs {
    size    = var.rootfs_size
    storage = var.rootfs_storage
  }

  features {
    nesting = var.features_nesting
  }

  network {
    ip     = var.network_ip
    name   = var.network_name
    bridge = var.network_bridge
    gw     = var.network_gw
  }

  lifecycle {
    ignore_changes = [
      description,
    ]
  }
}
