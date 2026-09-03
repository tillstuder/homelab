variable "cluster_name" {
  description = "Talos cluster name. Also the Kubernetes context name."
  type        = string
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint, e.g. https://10.42.5.200:6443. Points at the VIP when there is one, otherwise at the single control plane node."
  type        = string
}

variable "talos_version" {
  description = "Talos release"
  type        = string

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must look like v1.13.9."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes release"
  type        = string

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like v1.36.3."
  }
}

variable "machine_secrets_yaml" {
  description = "The Talos machine secrets bundle, verbatim, as `talosctl gen secrets` writes it."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "pve_node" {
  description = "Name of the Proxmox node the VMs are created on."
  type        = string
}

variable "datastore_vm" {
  description = "Datastore for VM disks and the cloud-init drive. Needs the `images` content type."
  type        = string
  default     = "local-lvm"
}

variable "datastore_iso" {
  description = "Datastore the Talos ISO is downloaded to. Needs the `iso` content type."
  type        = string
  default     = "local"
}

variable "bridge" {
  description = "Proxmox bridge the node NIC attaches to."
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "IPv4 default gateway for the node subnet."
  type        = string
}

variable "prefix" {
  description = "IPv4 prefix length of the node subnet."
  type        = number
  default     = 24
}

variable "vip" {
  description = "Shared control plane VIP. Null for single-node clusters, which have nothing to fail over to."
  type        = string
  default     = null
}

variable "pod_subnets" {
  description = "Pod CIDRs. Must not overlap another cluster on the same L2."
  type        = list(string)
}

variable "service_subnets" {
  description = "Service CIDRs. Must not overlap another cluster on the same L2."
  type        = list(string)
}

variable "nodes" {
  description = "The machines that make up the cluster, keyed by hostname."
  type = map(object({
    vm_id         = number
    ip            = string
    cores         = optional(number, 2)
    memory        = optional(number, 4096)
    disk_size     = optional(number, 32)
    control_plane = optional(bool, true)
  }))

  validation {
    condition     = length(var.nodes) > 0
    error_message = "A cluster needs at least one node."
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.vm_id])) == length(var.nodes)
    error_message = "Every node needs its own Proxmox VMID."
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.ip])) == length(var.nodes)
    error_message = "Every node needs its own IP address."
  }

  validation {
    condition     = length([for n in var.nodes : n if n.control_plane]) > 0
    error_message = "A cluster needs at least one control plane node."
  }
}

variable "bootstrap_node" {
  description = "Which node runs `talosctl bootstrap`. Exactly one, ever, for the life of the cluster."
  type        = string
}

variable "install_disk" {
  description = "Disk Talos installs itself to. /dev/sda is scsi0 on a virtio-scsi-single controller."
  type        = string
  default     = "/dev/sda"
}

variable "system_extensions" {
  description = "Talos Image Factory official extensions baked into the ISO and the installer."
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent"]
}

variable "shared_patches" {
  description = "Raw machine config patch documents applied to every node, in order. Fed from talos/patches/."
  type        = list(string)
  default     = []
}

variable "allow_scheduling_on_control_planes" {
  description = "Whether workloads may schedule onto control plane nodes."
  type        = bool
  default     = true
}

variable "apply_mode" {
  description = <<-EOT
    How `talos_machine_configuration_apply` lands a changed config.

    - `auto` reboots the node when the change needs it. That is right for the initial bootstrap, where every node is in maintenance mode and parallelism is free, and it is wrong for a day-2 change on a multi-node control plane, where OpenTofu would reboot every member at once and drop etcd quorum. Use
    - `staged_if_needing_reboot` there, or apply one node at a time with -target.
  EOT
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "reboot", "no_reboot", "staged", "try", "staged_if_needing_reboot"], var.apply_mode)
    error_message = "apply_mode must be one of auto, reboot, no_reboot, staged, try, staged_if_needing_reboot."
  }
}

variable "credentials_dir" {
  description = "Directory to write talosconfig and kubeconfig into, mode 0600. Null writes nothing."
  type        = string
  default     = null
}

variable "credentials_revision" {
  description = "Bump to force talosconfig and kubeconfig to be re-issued."
  type        = number
  default     = 1
}

variable "wait_for_cluster_health" {
  description = <<-EOT
    Block until Talos reports the cluster healthy.
    Turn this on once the CSRs are approved and you want plans to assert the cluster is still well.
  EOT
  type        = bool
  default     = false
}
