module "homer" {
  source          = "./modules/proxmox_lxc"
  vmid            = var.VMID_OFFSET + 0
  hostname        = "homer"
  description     = "Homer LXC"
  target_node     = var.PROXMOX_NODE_NAME
  ssh_public_keys = var.SSH_PUBLIC_KEY
  network_ip      = "${var.IP_HOMER}/${var.CIDR}"
  network_gw      = var.GATEWAY
}

module "adguardhome" {
  source          = "./modules/proxmox_lxc"
  vmid            = var.VMID_OFFSET + 1
  hostname        = "adguardhome"
  description     = "AdGuard Home LXC"
  target_node     = var.PROXMOX_NODE_NAME
  ssh_public_keys = var.SSH_PUBLIC_KEY
  network_ip      = "${var.IP_ADGUARDHOME}/${var.CIDR}"
  network_gw      = var.GATEWAY
  memory          = 1024
  swap            = 1024
}

module "ntfy" {
  source          = "./modules/proxmox_lxc"
  vmid            = var.VMID_OFFSET + 2
  hostname        = "ntfy"
  description     = "ntfy LXC"
  target_node     = var.PROXMOX_NODE_NAME
  ssh_public_keys = var.SSH_PUBLIC_KEY
  network_ip      = "${var.IP_NTFY}/${var.CIDR}"
  network_gw      = var.GATEWAY
}

module "gatus" {
  source          = "./modules/proxmox_lxc"
  vmid            = var.VMID_OFFSET + 3
  hostname        = "gatus"
  description     = "Gatus LXC"
  target_node     = var.PROXMOX_NODE_NAME
  ssh_public_keys = var.SSH_PUBLIC_KEY
  network_ip      = "${var.IP_GATUS}/${var.CIDR}"
  network_gw      = var.GATEWAY
  rootfs_size     = "4G"
}

module "tailscale" {
  source      = "./modules/proxmox_vm"
  vmid        = var.VMID_OFFSET + 4
  name        = "tailscale"
  desc        = "Tailscale VM"
  target_node = var.PROXMOX_NODE_NAME
  sshkeys     = var.SSH_PUBLIC_KEY
  ipconfig0   = "ip=${var.IP_TAILSCALE}/${var.CIDR},gw=${var.GATEWAY}"
  memory      = 1024
}


# Some examples of how to use the modules:

# module "lxc_test" {
#   source          = "./modules/proxmox_lxc"
#   vmid            = var.VMID_OFFSET + 1
#   hostname        = "lxctest"
#   description     = "Test LXC"
#   target_node     = var.PROXMOX_NODE_NAME
#   ssh_public_keys = var.SSH_PUBLIC_KEY
#   network_ip      = "0.0.0.10/${var.CIDR}"
#   network_gw      = var.GATEWAY
#   rootfs_size     = "4G"
# }

# module "vm_test" {
#   source      = "./modules/proxmox_vm"
#   vmid        = var.VMID_OFFSET + 2
#   name        = "vmtest" # Must be unique in the Proxmox cluster
#   desc        = "Test VM"
#   target_node = var.PROXMOX_NODE_NAME
#   sshkeys     = var.SSH_PUBLIC_KEY
#   ipconfig0   = "ip=0.0.0.11/${var.CIDR},gw=${var.GATEWAY}"
# }
