locals {
  talos_dir = "${path.module}/../../../talos"

  talenv = yamldecode(file("${local.talos_dir}/talenv.yaml"))

  shared_patches = [
    for f in fileset("${local.talos_dir}/patches", "*.yaml") :
    file("${local.talos_dir}/patches/${f}")
  ]

  domain = "lab.cyseclab.net"

  gateway_ip = "10.42.5.240"
}

module "cluster" {
  source = "../../modules/talos-cluster"

  cluster_name       = "prod"
  cluster_endpoint   = "https://10.42.5.200:6443"
  talos_version      = local.talenv.talosVersion
  kubernetes_version = local.talenv.kubernetesVersion

  machine_secrets_yaml = var.machine_secrets_yaml

  pve_node = var.pve_node

  gateway = "10.42.5.1"
  vip     = "10.42.5.200"

  pod_subnets     = ["10.244.0.0/16"]
  service_subnets = ["10.96.0.0/12"]

  nodes = {
    "prod-cp-1" = { vm_id = 201, ip = "10.42.5.201", memory = 6144 }
    "prod-cp-2" = { vm_id = 202, ip = "10.42.5.202", memory = 6144 }
    "prod-cp-3" = { vm_id = 203, ip = "10.42.5.203", memory = 6144 }
  }
  bootstrap_node = "prod-cp-1"

  shared_patches = local.shared_patches

  apply_mode = "staged_if_needing_reboot"

  credentials_dir = "${path.module}/.credentials"
}

data "cloudflare_zone" "this" {
  filter = {
    name = var.dns_zone
  }
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = data.cloudflare_zone.this.zone_id
  name    = "*.${local.domain}"
  type    = "A"
  content = local.gateway_ip
  ttl     = 300
  proxied = false
  comment = "Envoy Gateway for the prod cluster. Managed by OpenTofu."
}
