# Environment variables

variable "GATEWAY" {
  description = "IP of the network's gateway"
  type        = string
}

variable "CIDR" {
  description = "CIDR of the network. E.g.: 24"
  type        = number
}

variable "PROXMOX_NODE_NAME" {
  description = "Name of the Proxmox node"
  type        = string
}

variable "SSH_PUBLIC_KEY" {
  description = "Your SSH public key"
  type        = string
}

variable "IP_HOMER" {
  description = "IP of the Homer LXC"
  type        = string
}

variable "IP_ADGUARDHOME" {
  description = "IP of the AdGuard Home LXC"
  type        = string
}

variable "IP_NTFY" {
  description = "IP of the ntfy LXC"
  type        = string
}

variable "IP_GATUS" {
  description = "IP of the Gatus LXC"
  type        = string
}

variable "IP_TAILSCALE" {
  description = "IP of the Tailscale VM"
  type        = string
}

variable "VMID_OFFSET" {
  description = "Offset for the VMID"
  type        = number
}
