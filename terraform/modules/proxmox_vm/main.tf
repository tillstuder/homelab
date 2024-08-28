# Original Source: https://github.com/TechDufus/home.io/blob/main/terraform/proxmox/modules/proxmox_vm/main.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

resource "proxmox_vm_qemu" "virtual_machine" {

  vmid      = var.vmid
  name      = var.name
  desc      = var.desc
  cores     = var.cores
  sockets   = var.sockets
  memory    = var.memory
  onboot    = var.onboot
  tags      = var.tags
  ipconfig0 = var.ipconfig0

  target_node             = var.target_node
  cpu                     = var.cpu
  agent                   = var.agent
  qemu_os                 = var.qemu_os
  machine                 = var.machine
  tablet                  = var.tablet
  ciuser                  = var.ciuser
  sshkeys                 = var.sshkeys
  os_type                 = var.os_type
  clone                   = var.clone
  full_clone              = var.full_clone
  boot                    = var.boot
  scsihw                  = var.scsihw
  cloudinit_cdrom_storage = var.cloudinit_cdrom_storage

  disks {
    scsi {
      scsi0 {
        disk {
          size       = var.vm_disks_scsi_scsi0_disk_size
          cache      = var.vm_disks_scsi_scsi0_disk_cache
          discard    = var.vm_disks_scsi_scsi0_disk_discard
          emulatessd = var.vm_disks_scsi_scsi0_disk_emulatessd
          storage    = var.vm_disks_scsi_scsi0_disk_storage
        }
      }
    }
  }

  network {
    bridge   = var.network_bridge
    firewall = var.network_firewall
    model    = var.network_model
  }

  lifecycle {
    ignore_changes = [
      boot,
    ]
  }

}
