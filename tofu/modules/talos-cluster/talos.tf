ephemeral "talos_machine_configuration" "this" {
  for_each = toset([for n in var.nodes : n.control_plane ? "controlplane" : "worker"]) # so a cluster with no workers (e.g.: a single-node dev cluster) doesn't render a worker config that nobody consumes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = each.key
  machine_secrets    = local.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = concat([local.cluster_patch], var.shared_patches)
}

ephemeral "talos_client_configuration" "this" {
  cluster_name    = var.cluster_name
  machine_secrets = local.machine_secrets
  endpoints       = local.talos_endpoints
  nodes           = [for n in var.nodes : n.ip]
}

resource "talos_machine_configuration_apply" "this" {
  for_each = var.nodes

  client_configuration_wo        = ephemeral.talos_client_configuration.this.client_configuration
  machine_configuration_input_wo = ephemeral.talos_machine_configuration.this[each.value.control_plane ? "controlplane" : "worker"].machine_configuration

  node     = each.value.ip
  endpoint = each.value.ip

  config_patches = local.node_patches[each.key]

  apply_mode = var.apply_mode

  timeouts = {
    create = "15m"
    update = "15m"
  }

  depends_on = [proxmox_virtual_environment_vm.node]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration_wo = ephemeral.talos_client_configuration.this.client_configuration

  node     = var.nodes[var.bootstrap_node].ip
  endpoint = var.nodes[var.bootstrap_node].ip

  timeouts = {
    create = "15m"
  }

  depends_on = [talos_machine_configuration_apply.this]

  lifecycle {
    precondition {
      condition     = try(var.nodes[var.bootstrap_node].control_plane, false)
      error_message = "bootstrap_node must name a control plane node in var.nodes."
    }
  }
}

ephemeral "talos_cluster_health" "this" {
  count = var.wait_for_cluster_health ? 1 : 0

  client_configuration = ephemeral.talos_client_configuration.this.client_configuration
  endpoints            = local.talos_endpoints
  control_plane_nodes  = [for n in local.control_plane_nodes : n.ip]
  worker_nodes         = [for n in local.worker_nodes : n.ip]

  # The Kubernetes-level checks want Ready nodes, and nodes stay NotReady until a CNI exists.
  # But in our case, Cilium is Argo's job, so we assert only that Talos itself and etcd are healthy.
  skip_kubernetes_checks = true

  timeout = "15m"

  depends_on = [talos_machine_bootstrap.this]
}

ephemeral "talos_cluster_kubeconfig" "this" {
  cluster_name    = var.cluster_name
  machine_secrets = local.machine_secrets
  endpoint        = var.cluster_endpoint

  depends_on = [ephemeral.talos_cluster_health.this]
}

# Writing the credentials to disk, instead of exposing them to the state.
resource "terraform_data" "credentials" {
  count = var.credentials_dir == null ? 0 : 1
  input = var.credentials_dir

  triggers_replace = {
    cluster  = var.cluster_name
    endpoint = var.cluster_endpoint
    revision = var.credentials_revision
    configs  = sha256(join(",", [for a in talos_machine_configuration_apply.this : a.machine_configuration_hash]))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set -eu
      umask 077
      mkdir -p '${var.credentials_dir}'
      printf '%s' "$TALOSCONFIG_CONTENT" > '${var.credentials_dir}/talosconfig'
      printf '%s' "$KUBECONFIG_CONTENT"  > '${var.credentials_dir}/kubeconfig'
    EOT

    environment = {
      TALOSCONFIG_CONTENT = ephemeral.talos_client_configuration.this.talos_config
      KUBECONFIG_CONTENT  = ephemeral.talos_cluster_kubeconfig.this.kubeconfig_raw
    }
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "rm -f '${self.input}/talosconfig' '${self.input}/kubeconfig'"
  }
}
