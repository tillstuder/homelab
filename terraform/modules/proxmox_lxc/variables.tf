variable "vmid" {
  description = "ID of the node."
  type        = number
}

variable "hostname" {
  description = "Hostname of the node."
  type        = string
}

variable "description" {
  description = "Description of the node."
  type        = string
}

variable "cores" {
  description = "Number of cores."
  type        = number
  default     = 1
}

variable "memory" {
  description = "Amount of memory in MB."
  type        = number
  default     = 512
}

variable "swap" {
  description = "Amount of swap in MB."
  type        = number
  default     = 512
}

variable "onboot" {
  description = "Start the container on boot."
  type        = bool
  default     = true
}

variable "unprivileged" {
  description = "Run the container as unprivileged user."
  type        = bool
  default     = true
}

variable "start" {
  description = "Start the container after creation."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for the container."
  type        = string
  default     = "iac"
}

variable "target_node" {
  description = "Name of the target node."
  type        = string
}

variable "ostemplate" {
  description = "Name of the template."
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst"
}

variable "ssh_public_keys" {
  description = "SSH public keys."
  type        = string
}

variable "rootfs_size" {
  description = "Size of the root filesystem."
  type        = string
  default     = "2G"
}

variable "rootfs_storage" {
  description = "Storage for the root filesystem."
  type        = string
  default     = "local-lvm"
}

variable "features_nesting" {
  description = "Enable nesting."
  type        = bool
  default     = true
}

variable "network_ip" {
  description = "IP address of the container."
  type        = string
  default     = "dhcp"
}

variable "network_name" {
  description = "Name of the network interface."
  type        = string
  default     = "eth0"
}

variable "network_bridge" {
  description = "Name of the network bridge."
  type        = string
  default     = "vmbr0"
}

variable "network_gw" {
  description = "Gateway of the network."
  type        = string
}
