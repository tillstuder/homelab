output "cluster" {
  description = "How to reach this cluster. Credentials are written to .credentials/, not returned."
  value = {
    name            = module.cluster.cluster_name
    endpoint        = module.cluster.cluster_endpoint
    talos_endpoints = module.cluster.talos_endpoints
    nodes           = module.cluster.nodes
    credentials_dir = module.cluster.credentials_dir
    talos_image     = module.cluster.talos_image
  }
}

output "machine_configuration_hashes" {
  description = "SHA-256 of each node's applied machine config."
  value       = module.cluster.machine_configuration_hashes
}

output "wildcard_dns" {
  description = "The wildcard record pointing at this cluster's Gateway."
  value = {
    name    = cloudflare_dns_record.wildcard.name
    content = cloudflare_dns_record.wildcard.content
  }
}
