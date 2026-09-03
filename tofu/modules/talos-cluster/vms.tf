resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  node_name = var.pve_node
  vm_id     = each.value.vm_id
  name      = each.key
  tags      = [var.cluster_name]

  description = "Talos ${each.value.control_plane ? "control plane" : "worker"} for cluster ${var.cluster_name}. Managed by OpenTofu."

  on_boot       = true
  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0", "ide0"]

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = 0
  }

  disk {
    datastore_id = var.datastore_vm
    interface    = "scsi0"
    size         = each.value.disk_size
    ssd          = true
    discard      = "on"
    iothread     = true
    file_format  = "raw"
  }

  cdrom {
    interface = "ide0"
    file_id   = proxmox_download_file.talos.id
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore_vm
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.prefix}"
        gateway = var.gateway
      }
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  lifecycle {
    ignore_changes = [cdrom] # Talos upgrades itself
  }
}
