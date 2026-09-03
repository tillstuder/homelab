locals {
  talos_dir = "${path.module}/../../../talos"

  talenv = yamldecode(file("${local.talos_dir}/talenv.yaml"))

  shared_patches = [
    for f in fileset("${local.talos_dir}/patches", "*.yaml") :
    file("${local.talos_dir}/patches/${f}")
  ]

  domain = "dev.lab.cyseclab.net"

  gateway_ip = "10.42.5.248"
}

module "cluster" {
  source = "../../modules/talos-cluster"

  cluster_name       = "dev"
  cluster_endpoint   = "https://10.42.5.210:6443"
  talos_version      = local.talenv.talosVersion
  kubernetes_version = local.talenv.kubernetesVersion

  machine_secrets_yaml = var.machine_secrets_yaml

  pve_node = var.pve_node

  gateway = "10.42.5.1"
  vip     = null

  pod_subnets     = ["10.245.0.0/16"]
  service_subnets = ["10.112.0.0/12"]

  nodes = {
    "dev-cp-1" = { vm_id = 210, ip = "10.42.5.210", memory = 6144 }
  }
  bootstrap_node = "dev-cp-1"

  shared_patches = local.shared_patches

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
  comment = "Envoy Gateway for the dev cluster. Managed by OpenTofu."
}
