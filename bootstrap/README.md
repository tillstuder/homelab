# Bootstrap

This How To Guide assumes you'll bootstrap the cluster on a Proxmox host.

|            | prod                 | dev                    |
| ---------- | -------------------- | ---------------------- |
| Endpoint   | `10.42.5.200` (VIP)  | `10.42.5.210`          |
| Nodes      | `.201` `.202` `.203` | `.210`                 |
| LB pool    | `10.42.5.240-.247`   | `10.42.5.248-.251`     |
| Gateway IP | `10.42.5.240`        | `10.42.5.248`          |
| Domain     | `lab.cyseclab.net`   | `dev.lab.cyseclab.net` |
| 1P vault   | `homelab-prod`       | `homelab-dev`          |

## 0. Prerequisites

Tools:
- `talosctl`
- `talhelper`
- `helm`
- `kubectl`
- `op`
- `yq`
- `jq`

A domain hosted with Cloudflare with the following records:

| Record                   | Type | Value         | Proxy    |
| ------------------------ | ---- | ------------- | -------- |
| `*.lab.cyseclab.net`     | `A`  | `10.42.5.240` | DNS only |
| `*.dev.lab.cyseclab.net` | `A`  | `10.42.5.248` | DNS only |

> [!WARNING]
> The DNS records be DNS only (grey cloud) because the Gateway is on a private RFC1918 address.
> Orange-clouding them breaks the Gateway's HTTPS listener.

## 1. Create the Proxmox VMs

Talos is immutable and nothing here is managed by this repo, so each VM needs only a disk and a NIC.

Fetch the ISO first, its version must match `talosVersion` in `talos/talenv.yaml`:
```sh
ssh pvelaptop 'curl -fsSL -o /var/lib/vz/template/iso/talos-v1.13.9-metal-amd64.iso https://github.com/siderolabs/talos/releases/download/v1.13.9/metal-amd64.iso'
```

The expected configuration is:
- **Bridge** `vmbr0`, on `10.42.5.0/24` with gateway `10.42.5.1`
- **NIC** `net0` as `virtio`
- **Disk** `scsi0` on a `virtio-scsi-single` controller, which the guest sees as `/dev/sda`
- **Storage** `local-lvm` for disks, `local` for ISOs
- **VMIDs** the `300` block, last two digits matching the IP, so `301` is `10.42.5.201`

| VM        | VMID  | IP            | RAM   | vCPU | Disk  |
| --------- | ----- | ------------- | ----- | ---- | ----- |
| prod-cp-1 | `301` | `10.42.5.201` | 4 GiB | 2    | 32 GB |
| prod-cp-2 | `302` | `10.42.5.202` | 4 GiB | 2    | 32 GB |
| prod-cp-3 | `303` | `10.42.5.203` | 4 GiB | 2    | 32 GB |
| dev-cp-1  | `310` | `10.42.5.210` | 4 GiB | 2    | 32 GB |

Create them:

```sh
ssh pvelaptop 'set -e
ISO=local:iso/talos-v1.13.9-metal-amd64.iso
create() {
  qm create $1 --name $2 \
    --memory $3 --balloon 0 --cores $4 --cpu host --numa 0 \
    --ostype l26 --machine q35 \
    --scsihw virtio-scsi-single --scsi0 local-lvm:32,discard=on,ssd=1 \
    --net0 virtio,bridge=vmbr0 \
    --ide2 $ISO,media=cdrom \
    --boot "order=scsi0;ide2" \
    --serial0 socket --vga serial0 \
    --onboot 1
}
create 301 prod-cp-1 4096 2
create 302 prod-cp-2 4096 2
create 303 prod-cp-3 4096 2
create 310 dev-cp-1  4096 2'
```

> [!NOTE]
> `--boot "order=scsi0;ide2"` makes the empty disk fall through to the ISO on first boot and take over once Talos installs itself, so the CDROM never has to be detached by hand.

Start the prod nodes:

```sh
ssh pvelaptop 'for id in 301 302 303; do qm start $id; done'
```

## 2. Identify the nodes in maintenance mode

Until a config is applied the nodes take **DHCP** addresses, not their final ones.
Find them by their Talos API port, then map each address to its VM by MAC, otherwise there is no way to know which node should get which config:

```sh
ssh pvelaptop 'nmap -n -Pn -p 50000 --open 10.42.5.1/24 -oG - | awk "/50000\/open/{print \$2}"'
ssh pvelaptop 'for id in 301 302 303; do qm config $id | grep -oE "virtio=[0-9A-F:]+"; done'
ssh pvelaptop 'ip neigh show dev vmbr0'
```

> [!TIP]
> Confirm the disk and NIC the machine config references:
> ```sh
> talosctl get disks -n <dhcp-ip> --insecure
> talosctl get links -n <dhcp-ip> --insecure -o yaml | grep -E 'id:|driver:'
> ```

On this VM the install disk is `/dev/sda` and the NIC is `ens18` with driver `virtio_net`.

## 3. Generate machine secrets

```sh
cd talos
talhelper gensecret > talsecret-prod.yaml
talhelper gensecret > talsecret-dev.yaml

op document create talsecret-prod.yaml --title "talsecret-prod" --vault homelab-prod
op document create talsecret-dev.yaml  --title "talsecret-dev"  --vault homelab-dev
```

## 4. Generate and apply machine configs

```sh
talhelper genconfig \
  --config-file talconfig-prod.yaml \
  --env-file    talenv.yaml \
  --secret-file talsecret-prod.yaml
```

> [!NOTE]
> `talenv.yaml` is talhelper's **variable file**.
> It only takes effect because `talconfig-<cluster>.yaml` uses it:
> ```yaml
> talosVersion: ${talosVersion}
> kubernetesVersion: ${kubernetesVersion}
> ```

Apply each config to that node's **DHCP** address from step 2:

```sh
export TALOSCONFIG=./clusterconfig/talosconfig
talosctl apply-config --insecure -n <dhcp-ip> -f clusterconfig/prod-prod-cp-1.yaml
# ...repeat per node
```

Each node installs to disk, reboots, and returns on its static address:

```sh
ssh pvelaptop 'nmap -n -Pn -p 50000 --open 10.42.5.1/24 -oG - | awk "/50000\/open/{print \$2}"'
```

## 5. Bootstrap etcd

Important: Do this only once on a single control-plane node:

```sh
export TALOSCONFIG=./clusterconfig/talosconfig
talosctl bootstrap -n 10.42.5.201
```

Once the members have joined, fetch the credentials:

```sh
talosctl etcd members -n 10.42.5.201
talosctl kubeconfig . -n 10.42.5.201
export KUBECONFIG=$PWD/kubeconfig
```

> [!WARNING]
> Nodes stay `NotReady` until Cilium is installed.

### Approve the kubelet serving certificates

`talos/patches/kubelet.yaml` sets `serverTLSBootstrap: true`, so every kubelet requests a serving certificate through a CSR.

Until they are approved, `kubectl logs`, `exec` and `top` fail with `remote error: tls: internal error`:
```sh
kubectl get csr -o name --field-selector spec.signerName=kubernetes.io/kubelet-serving | xargs -n1 kubectl certificate approve
```

## 6. Install Cilium

Talos ships with `cniConfig: none` and kube-proxy disabled, so nothing networks until Cilium is installed.
Install it with **the same value files Argo will use**, so the Application adopts the release later instead of fighting it:

```sh
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.1 \
  --namespace kube-system \
  -f ../infrastructure/base/cilium/values.yaml \
  -f ../clusters/prod/values/cilium.yaml
```

All nodes should reach `Ready` about a minute later.

## 7. Install Argo CD and the 1Password token

Same approach, the value files the Application will later use:

```sh
helm install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f ../infrastructure/base/argo-cd/values.yaml \
  -f ../clusters/prod/values/argo-cd.yaml
```

Create the 1Password service account.

One account per cluster, scoped to that cluster's vault only, so a compromised dev cluster cannot read prod credentials:

```sh
op service-account create "homelab-prod" --vault "homelab-prod:read_items" --raw
```

Store the token in the matching vault as an **API Credential** item titled `Service Account Auth Token` with field `credential`.

Then hand it to the cluster:

```sh
kubectl create namespace external-secrets
kubectl create secret generic onepassword-token \
  --namespace external-secrets \
  --from-literal=token="$(op read 'op://homelab-prod/Service Account Auth Token/credential')"
```

> [!TIP]
> To revoke or rotate these tokens, visit: https://my.1password.com/developer-tools/active/service-accounts

### What each vault must contain

The ExternalSecrets resolve against these.

| Item                         | Field        | Used by                                                   |
| ---------------------------- | ------------ | --------------------------------------------------------- |
| `Service Account Auth Token` | `credential` | the `onepassword-token` secret above                      |
| `cloudflare`                 | `api-token`  | cert-manager DNS-01 (`ClusterIssuer`), via ExternalSecret |
| `talsecret-<cluster>`        | (document)   | disaster recovery only                                    |

The `cloudflare` item needs an API token with **Zone → DNS → Edit** & **Zone → Zone → Read** on `cyseclab.net`.

The tokens can be created at https://dash.cloudflare.com/profile/api-tokens using the template `Edit zone DNS`.

## 8. Hand over to Argo

```sh
kubectl apply -f ../clusters/prod/root.yaml
kubectl -n argocd get applications -w
```

Every Application should reach `Synced`/`Healthy`.

`cilium` remains `Progressing` while any node is down as its a DaemonSet.

> [!TIP] Argo's initial admin password:
> ```sh
> kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath='{.data.password}' | base64 -d
> ```
