# Day-2 operations <!-- omit in toc -->

- [Talos or Kubernetes upgrade](#talos-or-kubernetes-upgrade)
  - [1. Render the new version into the machine config](#1-render-the-new-version-into-the-machine-config)
  - [2. Upgrade Talos, one node at a time](#2-upgrade-talos-one-node-at-a-time)
  - [3. Upgrade Kubernetes](#3-upgrade-kubernetes)
- [Re-issuing client certificates](#re-issuing-client-certificates)
- [Resizing a node](#resizing-a-node)
- [Removing a cluster node](#removing-a-cluster-node)
- [Adopting existing DNS records](#adopting-existing-dns-records)

## Talos or Kubernetes upgrade

Both versions live in `talos/talenv.yaml` and both clusters read it, so a bump is one file:

```yaml
# renovate: datasource=github-releases depName=siderolabs/talos
talosVersion: "v1.13.9"
# renovate: datasource=github-releases depName=kubernetes/kubernetes
kubernetesVersion: "v1.36.3"
```

### 1. Render the new version into the machine config

```sh
op run --env-file=.env -- tofu apply
```

Expect exactly two kinds of change:

- `proxmox_download_file.talos` replaced, because the ISO URL and name carry the version
- `talos_machine_configuration_apply.this` updated per node, because `machine.install.image` points at the new Image Factory installer

### 2. Upgrade Talos, one node at a time

```sh
export TALOSCONFIG=$PWD/.credentials/talosconfig
INSTALLER=$(op run --env-file=.env -- tofu output -json cluster | jq -r '.talos_image.installer')

talosctl -n 10.42.5.201 upgrade --image "$INSTALLER"
```

Talos cordons and drains the node, writes the new release, reboots, and applies the staged config on the way back up.
Wait for it to come back healthy before touching the next one:

```sh
talosctl -n 10.42.5.201 version
talosctl -n 10.42.5.201 service etcd
kubectl get nodes
```

Then repeat for `10.42.5.202` and `10.42.5.203`.

> [!WARNING]
> On `dev`, a single control plane node, pass `--preserve`.
> Without it the upgrade wipes `EPHEMERAL`, and with one member that is the whole etcd:
> ```sh
> talosctl -n 10.42.5.210 upgrade --image "$INSTALLER" --preserve
> ```

### 3. Upgrade Kubernetes

Once every node runs the new Talos, run the following command against any control plane node:

```sh
talosctl -n 10.42.5.201 upgrade-k8s --to v1.36.3
```

It rolls the control plane static pods and the kubelets node by node and updates the Talos-managed add-ons.

```sh
kubectl get nodes -o wide
kubectl -n kube-system get pods
```

> [!WARNING]
> Don't skip a Kubernetes minor version.
> `v1.35 -> v1.36 -> v1.37`, one at a time, with the cluster healthy in between.

## Re-issuing client certificates

```sh
op run --env-file=.env -- tofu apply -replace='module.cluster.terraform_data.credentials[0]'
```

## Resizing a node

`cores` and `memory` are per-node keys in the `nodes` map, so a resize is one line per node:

```hcl
nodes = {
  "prod-cp-1" = { vm_id = 201, ip = "10.42.5.201", memory = 6144 }
  "prod-cp-2" = { vm_id = 202, ip = "10.42.5.202", memory = 6144 }
  "prod-cp-3" = { vm_id = 203, ip = "10.42.5.203", memory = 6144 }
}
```

But the three control plane VMs do not depend on each other, so a plain `tofu apply` reboots all three at once and etcd loses quorum.

So we have to go one node at a time:

```sh
op run --env-file=.env -- tofu apply \
  -target='module.cluster.proxmox_virtual_environment_vm.node["prod-cp-1"]'
```

Wait for it to come back healthy before touching the next one:

```sh
export TALOSCONFIG=$PWD/.credentials/talosconfig
talosctl -n 10.42.5.201 service etcd
kubectl get nodes -o custom-columns='NODE:.metadata.name,MEM:.status.capacity.memory'
```

## Removing a cluster node

Evict it from etcd first, then destroy:

```sh
talosctl -n 10.42.5.203 etcd remove-member prod-cp-3
op run --env-file=.env -- tofu apply
```

## Adopting existing DNS records

A cluster whose wildcard record already exists in Cloudflare needs it imported once, or the first apply creates a duplicate:

```sh
ZONE=$(op run --env-file=.env -- tofu console <<< 'data.cloudflare_zone.this.zone_id')
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records?name=*.lab.cyseclab.net" \
  -H "Authorization: Bearer $(op read 'op://homelab-prod/cloudflare/api-token')" | jq -r '.result[].id'

op run --env-file=.env -- tofu import cloudflare_dns_record.wildcard "$ZONE/<record-id>"
```
