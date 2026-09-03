variable "machine_secrets_yaml" {
  description = "Talos machine secrets bundle for this cluster."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "pve_hosts" {
  description = "Proxmox nodes in the lab, keyed by node name -> API endpoint."
  type        = map(string)
  default = {
    pvebig    = "https://10.42.5.10:8006/"
    pvesmall  = "https://10.42.5.11:8006/"
    pvelaptop = "https://10.42.5.12:8006/"
  }
}

variable "pve_node" {
  description = "Proxmox node the cluster's VMs are created on. Must be a key of pve_hosts."
  type        = string
  default     = "pvesmall"

  validation {
    condition     = contains(keys(var.pve_hosts), var.pve_node)
    error_message = "pve_node must be one of: ${join(", ", keys(var.pve_hosts))}."
  }
}

variable "pve_insecure" {
  description = <<-EOT
    Skip TLS verification against Proxmox.
    True because Proxmox serves its own self-signed certificate by default.
  EOT
  type        = bool
  default     = true
}

variable "dns_zone" {
  description = "Cloudflare zone the cluster's wildcard record lives in."
  type        = string
  default     = "cyseclab.net"
}
