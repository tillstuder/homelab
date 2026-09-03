locals {
  secrets_yaml = yamldecode(var.machine_secrets_yaml)

  machine_secrets = {
    cluster = {
      id     = local.secrets_yaml.cluster.id
      secret = local.secrets_yaml.cluster.secret
    }
    secrets = {
      bootstrap_token             = local.secrets_yaml.secrets.bootstraptoken
      secretbox_encryption_secret = local.secrets_yaml.secrets.secretboxencryptionsecret
      aescbc_encryption_secret    = try(local.secrets_yaml.secrets.aescbcencryptionsecret, null)
    }
    trustdinfo = {
      token = local.secrets_yaml.trustdinfo.token
    }
    certs = {
      etcd               = { cert = local.secrets_yaml.certs.etcd.crt, key = local.secrets_yaml.certs.etcd.key }
      k8s                = { cert = local.secrets_yaml.certs.k8s.crt, key = local.secrets_yaml.certs.k8s.key }
      k8s_aggregator     = { cert = local.secrets_yaml.certs.k8saggregator.crt, key = local.secrets_yaml.certs.k8saggregator.key }
      k8s_serviceaccount = { key = local.secrets_yaml.certs.k8sserviceaccount.key }
      os                 = { cert = local.secrets_yaml.certs.os.crt, key = local.secrets_yaml.certs.os.key }
    }
  }

  control_plane_nodes = { for k, n in var.nodes : k => n if n.control_plane }
  worker_nodes        = { for k, n in var.nodes : k => n if !n.control_plane }

  endpoint_host   = replace(replace(var.cluster_endpoint, "https://", ""), ":6443", "")
  talos_endpoints = [for n in local.control_plane_nodes : n.ip]

  cluster_patch = yamlencode({
    cluster = {
      allowSchedulingOnControlPlanes = var.allow_scheduling_on_control_planes
      network = {
        cni            = { name = "none" }
        podSubnets     = var.pod_subnets
        serviceSubnets = var.service_subnets
      }
      apiServer = {
        certSANs = distinct(compact(concat([local.endpoint_host, var.vip], [for n in local.control_plane_nodes : n.ip])))
      }
    }
  })

  node_patches = {
    for name, n in var.nodes : name => [
      # Talos >=1.12 generated HostnameConfig sets auto: stable, which a strategic merge can't unset and which can't coexist with hostname.
      # So the document is deleted and replaced with a static one:
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        "$patch"   = "delete"
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = name
      }),
      yamlencode({
        machine = {
          install = {
            disk  = var.install_disk
            image = data.talos_image_factory_urls.this.urls.installer
          }
          certSANs = distinct(compact([n.ip, var.vip]))
          network = {
            interfaces = [
              merge(
                {
                  deviceSelector = { driver = "virtio_net" }
                  dhcp           = false
                  addresses      = ["${n.ip}/${var.prefix}"]
                  routes         = [{ network = "0.0.0.0/0", gateway = var.gateway }]
                },
                var.vip == null || !n.control_plane ? {} : { vip = { ip = var.vip } },
              )
            ]
          }
        }
      }),
    ]
  }
}
