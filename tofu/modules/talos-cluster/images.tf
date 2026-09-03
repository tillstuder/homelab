resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.system_extensions
      }
    }
  })
}

locals {
  image_architecture = "amd64"
  image_platform     = "nocloud"
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  architecture  = local.image_architecture
  platform      = local.image_platform
}

resource "proxmox_download_file" "talos" {
  node_name      = var.pve_node
  datastore_id   = var.datastore_iso
  content_type   = "iso"
  url            = data.talos_image_factory_urls.this.urls.iso
  file_name      = "talos-${var.cluster_name}-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 12)}-${local.image_platform}-${local.image_architecture}.iso"
  upload_timeout = 900
}
