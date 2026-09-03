output "cluster_name" {
  description = "Talos cluster name."
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = var.cluster_endpoint
}

output "talos_endpoints" {
  description = "Addresses talosctl should use as -e endpoints."
  value       = local.talos_endpoints
}

output "nodes" {
  description = "Node hostname to address, VMID and role."
  value = {
    for k, n in var.nodes : k => {
      ip            = n.ip
      vm_id         = n.vm_id
      control_plane = n.control_plane
    }
  }
}

output "talos_image" {
  description = "The Image Factory schematic and ISO backing this cluster."
  value = {
    schematic_id = talos_image_factory_schematic.this.id
    iso          = proxmox_download_file.talos.id
    installer    = data.talos_image_factory_urls.this.urls.installer
  }
}

output "machine_configuration_hashes" {
  description = "SHA-256 of each node's rendered machine config."
  value       = { for k, a in talos_machine_configuration_apply.this : k => a.machine_configuration_hash }
}

output "credentials_dir" {
  description = "Where talosconfig and kubeconfig were written, if anywhere."
  value       = var.credentials_dir
}
