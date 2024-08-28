variable "vmid" {
  description = "ID of the node."
  type        = number
}

variable "name" {
  description = "Name of the VM"
  type        = string
}

variable "desc" {
  description = "Description of the VM"
  type        = string
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 1
}

variable "sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Amount of memory in MB"
  type        = number
  default     = 2048
}

variable "onboot" {
  description = "Whether the VM should start on boot"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for the VM"
  type        = string
  default     = "iac"
}

variable "ipconfig0" {
  description = "IP configuration for the VM"
  type        = string
  default     = "ip=dhcp"
}

variable "target_node" {
  description = "Target node for the VM"
  type        = string
}

variable "cpu" {
  description = "Which CPU to use"
  type        = string
  default     = "host"
}

variable "agent" {
  description = "Whether the QEMU guest agent is installed"
  type        = number
  default     = 0
}

variable "qemu_os" {
  description = "Which OS to use"
  type        = string
  default     = "l26"
}

variable "machine" {
  description = "Which machine to use"
  type        = string
  default     = "q35"
}

variable "tablet" {
  description = "Whether to use a tablet"
  type        = bool
  default     = true
}

variable "ciuser" {
  description = "Cloud-init user"
  type        = string
  default     = "root"
}

variable "sshkeys" {
  description = "SSH public key"
  type        = string
}

variable "os_type" {
  description = "Which OS type to use"
  type        = string
  default     = "cloud-init"
}

variable "clone" {
  description = "Template name to clone from"
  type        = string
  default     = "debian-12-template"
}

variable "full_clone" {
  description = "Whether to use a full clone"
  type        = bool
  default     = true
}

variable "boot" {
  description = "Boot order"
  type        = string
  default     = "order=scsi0;ide3"
}

variable "scsihw" {
  description = "Which SCSI hardware to use"
  type        = string
  default     = "virtio-scsi-single"
}

variable "cloudinit_cdrom_storage" {
  description = "Storage for the cloud-init CD-ROM"
  type        = string
  default     = "local-lvm"
}

variable "vm_disks_scsi_scsi0_disk_size" {
  description = "Size of the disk in GB"
  type        = number
  default     = 8
}

variable "vm_disks_scsi_scsi0_disk_cache" {
  description = "Disk cache for the VM"
  type        = string
  default     = "writeback"
}

variable "vm_disks_scsi_scsi0_disk_discard" {
  description = "Whether to discard the disk"
  type        = bool
  default     = true
}

variable "vm_disks_scsi_scsi0_disk_emulatessd" {
  description = "Whether to emulate an SSD"
  type        = bool
  default     = true
}

variable "vm_disks_scsi_scsi0_disk_storage" {
  description = "Storage for the VM"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Bridge for the VM"
  type        = string
  default     = "vmbr0"
}

variable "network_firewall" {
  description = "Firewall for the VM"
  type        = bool
  default     = false
}

variable "network_model" {
  description = "Network model for the VM"
  type        = string
  default     = "virtio"
}

