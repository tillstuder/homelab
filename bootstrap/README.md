# Bootstrap

Both `prod` and `dev` follow the same steps, please substitute the cluster name and, where noted, the differing IP.

`10.42.5.20-.199` is the DHCP range, so everything assigned here sits in `.200-.254`.

|            | prod                 | dev                    |
| ---------- | -------------------- | ---------------------- |
| Endpoint   | `10.42.5.200` (VIP)  | `10.42.5.210`          |
| Nodes      | `.201` `.202` `.203` | `.210`                 |
| LB pool    | `10.42.5.240-.247`   | `10.42.5.248-.251`     |
| Gateway IP | `10.42.5.240`        | `10.42.5.248`          |
| Domain     | `lab.cyseclab.net`   | `dev.lab.cyseclab.net` |
| 1P vault   | `homelab-prod`       | `homelab-dev`          |

Everything below was executed end-to-end against `pvelaptop` and reflects what
actually happened, not what ought to happen.

## 0. Prerequisites

| Tool       | Notes                                                                         |
| ---------- | ----------------------------------------------------------------------------- |
| `talosctl` | Match the minor version in `talos/talenv.yaml`. `brew install siderolabs/tap/talosctl` |
| `talhelper`| **The Homebrew tap `budimanjojo/tap` is gone (404).** Install the release binary instead (below) |
| `helm`     | v4.x. See the repo-config caveat in step 6                                    |
| `kubectl`  |                                                                               |
| `op`       | 1Password CLI, signed in (`op vault list` must succeed)                        |
| `yq`, `jq` |                                                                               |

```sh
# talhelper — the brew tap no longer exists, so take the release binary
VER=3.1.16   # or the current release
curl -sSL -o /tmp/th.tar.gz \
  "https://github.com/budimanjojo/talhelper/releases/download/v${VER}/talhelper_darwin_arm64.tar.gz"
tar -xzf /tmp/th.tar.gz -C /tmp talhelper
install -m 0755 /tmp/talhelper /opt/homebrew/bin/talhelper
```

> [!NOTE] **Where you run this from matters.**
> The workstation is on `10.42.2.0/24`, while the cluster lives on `10.42.5.0/24`.
> Reachability comes from the `tailscale` VM (VMID `100`) advertising `10.42.5.0/24`
> as a subnet route — `route -n get 10.42.5.12` should resolve via `utun*`.
> If Tailscale is down, nothing below can reach the nodes, and `nmap`-based
> discovery has to be run from `pvelaptop` itself (which is what the commands here do).

## 1. Proxmox VMs

Only a Debian ISO is on the host, so fetch the Talos one first. The version must
match `talosVersion` in `talos/talenv.yaml`:

```sh
ssh pvelaptop 'curl -fsSL -o /var/lib/vz/template/iso/talos-v1.13.9-metal-amd64.iso \
  https://github.com/siderolabs/talos/releases/download/v1.13.9/metal-amd64.iso'
```

Nothing here is managed by this repo, Talos is immutable, so each VM only needs a disk and a NIC.

On `pvelaptop` (single node, `10.42.5.12`, i7-7500U / 2 cores / 4 threads, 15 GiB RAM):

- **Bridge**: `vmbr0` — the only bridge, already on `10.42.5.0/24`, gateway `10.42.5.1`
- **NIC**: `net0` as `virtio`, which the machine config selects with `driver: virtio_net`
- **Disk**: `scsi0` on a `virtio-scsi-single` controller, which the guest sees as `/dev/sda`
- **Storage**: `local-lvm` (LVM-thin, ~808 GiB free). ISOs go to `local`.
- **VMIDs**: the `300` block, with the last two digits matching the IP's last two, so `301` is `10.42.5.201` and `310` is `10.42.5.210`.

| VM        | VMID  | IP            | RAM   | vCPU | Disk  |
| --------- | ----- | ------------- | ----- | ---- | ----- |
| prod-cp-1 | `301` | `10.42.5.201` | 2 GiB | 1    | 32 GB |
| prod-cp-2 | `302` | `10.42.5.202` | 2 GiB | 1    | 32 GB |
| prod-cp-3 | `303` | `10.42.5.203` | 2 GiB | 1    | 32 GB |
| dev-cp-1  | `310` | `10.42.5.210` | 4 GiB | 2    | 32 GB |

That is 10 GiB of the ~11 GiB left after the host, the `tailscale` VM and the
`runtipi` LXC, so **prod and dev do not comfortably run at the same time**.
Bootstrap prod first, and stop `301-303` before starting `310` if memory gets tight.
Disk is not a constraint — the thin pool has ~808 GiB free.

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
create 301 prod-cp-1 2048 1
create 302 prod-cp-2 2048 1
create 303 prod-cp-3 2048 1
create 310 dev-cp-1  4096 2'
```

`--balloon 0` pins memory (no ballooning) and `--boot "order=scsi0;ide2"` means
the empty disk falls through to the ISO on the first boot and takes over once
Talos has installed itself, so the CDROM never has to be detached by hand.

Start the prod nodes:

```sh
ssh pvelaptop 'for id in 301 302 303; do qm start $id; done'
```

## 2. Find the nodes in maintenance mode

Before a config is applied the nodes take a **DHCP** address, not their final one.
Find them by their Talos API port, then map each one to its VM by MAC — otherwise
there is no way to know which node should get which config:

```sh
ssh pvelaptop 'nmap -n -Pn -p 50000 --open 10.42.5.20-199 -oG - | awk "/50000\/open/{print \$2}"'
ssh pvelaptop 'for id in 301 302 303; do qm config $id | grep -oE "virtio=[0-9A-F:]+"; done'
ssh pvelaptop 'ip neigh show dev vmbr0'
```

Now confirm the disk and NIC the machine config references:

```sh
talosctl get disks -n <dhcp-ip> --insecure
talosctl get links -n <dhcp-ip> --insecure -o yaml | grep -E 'id:|driver:'
```

> [!IMPORTANT] `talosctl disks --insecure` no longer exists in Talos 1.13 — the
> flag was dropped. Use the resource API (`talosctl get disks`) shown above.

Verified on this hardware: the install disk is `/dev/sda` (`virtio` transport,
34 GB) and the single NIC is `ens18` with driver `virtio_net`. The talconfigs
select the NIC by `driver: virtio_net` rather than a `busPath` glob, because the
bus path (`0000:06:12.0`) is an implementation detail that moves with the machine type.

## 3. Machine secrets

**Each cluster needs its own secret bundle** — a shared one would let dev's PKI
sign for prod. `.gitignore` covers `talos/talsecret*.yaml`.

```sh
cd talos
talhelper gensecret > talsecret-prod.yaml
talhelper gensecret > talsecret-dev.yaml

op document create talsecret-prod.yaml --title "talsecret-prod" --vault homelab-prod
op document create talsecret-dev.yaml  --title "talsecret-dev"  --vault homelab-dev
```

## 4. Generate and apply machine configs

`talenv.yaml` is talhelper's **variable file**, not a config file — it only has an
effect because `talconfig-<cluster>.yaml` interpolates it:

```yaml
talosVersion: ${talosVersion}
kubernetesVersion: ${kubernetesVersion}
```

Without those two lines the pins in `talenv.yaml` (and the Renovate comments
above them) are silently ignored and talhelper falls back to its own built-in
defaults. `talenv.yaml` is picked up automatically, so `--env-file` is optional.

```sh
talhelper genconfig \
  --config-file talconfig-prod.yaml \
  --env-file    talenv.yaml \
  --secret-file talsecret-prod.yaml
```

talhelper warns `"v1.13.9" might not be compatible with this Talhelper version` —
that is just its bundled compatibility table lagging the Talos release, and the
generated config is fine.

Apply each config to the **DHCP** address from step 2:

```sh
export TALOSCONFIG=./clusterconfig/talosconfig
talosctl apply-config --insecure -n <dhcp-ip> -f clusterconfig/prod-prod-cp-1.yaml
# ...repeat per node
```

The nodes install to disk, reboot, and come back on their static addresses:

```sh
ssh pvelaptop 'nmap -n -Pn -p 50000 --open 10.42.5.201-203 -oG - | awk "/50000\/open/{print \$2}"'
```

> [!NOTE] Talos 1.13 emits a **multi-document** machine config. Networking is no
> longer under `machine.network` but in separate `HostnameConfig`, `LinkAliasConfig`,
> `LinkConfig` and `Layer2VIPConfig` documents. To inspect one:
> `yq -r 'select(documentIndex==0)' clusterconfig/prod-prod-cp-1.yaml`

## 5. Bring up the cluster

talhelper already writes the endpoints and nodes into `clusterconfig/talosconfig`,
so there is no need to run `talosctl config endpoint/node` by hand. Confirm with
`talosctl config info`.

```sh
export TALOSCONFIG=./clusterconfig/talosconfig
talosctl bootstrap -n 10.42.5.201   # only once, on a single control-plane node
```

> [!IMPORTANT] Until `bootstrap` runs, every node sits at `STAGE=booting` with
> `etcd` in `Preparing`/`Running pre state`. That is not a failure — the control
> plane simply has no etcd to start against. Do not wait for `running` before
> bootstrapping; it will never arrive.

Then, once all three etcd members have joined:

```sh
talosctl etcd members -n 10.42.5.201
talosctl kubeconfig . -n 10.42.5.201
export KUBECONFIG=$PWD/kubeconfig
```

Nodes stay `NotReady` until step 6, that is expected, as there is no CNI yet.

### Approve the kubelet serving certificates

`talos/patches/kubelet.yaml` sets `serverTLSBootstrap: true`, so each kubelet
requests a serving cert through a CSR — and **nothing in this repo approves them**.
Until they are approved, `kubectl logs`, `kubectl exec` and `kubectl top` all fail with
`remote error: tls: internal error`.

```sh
kubectl get csr -o name --field-selector spec.signerName=kubernetes.io/kubelet-serving \
  | xargs -n1 kubectl certificate approve
```

> [!WARNING] This is a stopgap. `rotate-server-certificates` means the certs are
> reissued periodically and each rotation lands as a new Pending CSR. A real fix
> is a `kubelet-csr-approver` deployment — see the README's Next section.

## 6. Cilium

Talos ships with `cniConfig: none` and kube-proxy disabled, so nothing networks until Cilium is installed. This is a one-shot install using **the same value files Argo will use**, so the Application adopts it cleanly instead of fighting it.

> [!IMPORTANT] Helm 4 validates the cache of **every** repo in your global
> `repositories.yaml` when `--repo` is used, so one stale entry elsewhere on your
> machine breaks an unrelated install with `no cached repo found`. Point Helm at
> an empty repo config to make the command independent of local state:
>
> ```sh
> export HELM_REPOSITORY_CONFIG=$(mktemp)
> ```

```sh
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.1 \
  --namespace kube-system \
  -f ../infrastructure/base/cilium/values.yaml \
  -f ../clusters/prod/values/cilium.yaml
```

Nodes go `Ready` about a minute later.

## 7. Argo CD, and the 1Password token

Same trick, install with the value files the Application will later use.

```sh
helm install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f ../infrastructure/base/argo-cd/values.yaml \
  -f ../clusters/prod/values/argo-cd.yaml
```

> [!NOTE] Argo CD's `HTTPRoute` deliberately lives in the separate
> `argo-cd-config` Application (sync-wave 6), **not** in these values. The Gateway
> API CRDs only arrive with Envoy Gateway at wave 5, so a wave-0 chart that
> renders an `HTTPRoute` fails both here (`no matches for kind "HTTPRoute"`) and
> later inside Argo, where wave 0 could never go Healthy and the app-of-apps
> would stall before ever reaching wave 5.

The ClusterSecretStore authenticates with a 1Password service account token.

Create it before Argo syncs External Secrets, so the store is valid the first time it reconciles:

```sh
# one service account per cluster, scoped to that cluster's vault only
op service-account create "homelab-prod" --vault "homelab-prod:read_items" --raw
```

> [!CAUTION] In **zsh**, write the vault argument as `"homelab-${env}:read_items"`.
> Unbraced `"homelab-$env:read_items"` is mangled into `homelab-prodead_items`,
> because zsh applies its `:r` ("remove extension") modifier to `$env`.

Store the token in the matching vault as an **API Credential** item titled
`Service Account Auth Token`, field `credential`, then hand it to the cluster:

```sh
kubectl create namespace external-secrets
kubectl create secret generic onepassword-token \
  --namespace external-secrets \
  --from-literal=token="$(op read 'op://homelab-prod/Service Account Auth Token/credential')"
```

Note the vault differs per cluster: `homelab-prod` and `homelab-dev` have separate service accounts, so a wiped or compromised dev cluster cannot read prod credentials.

### Vault contents

Each vault must also hold the secrets the ExternalSecrets resolve, or cert-manager
never issues the wildcard certificate and the Gateway's HTTPS listener stays broken:

| Item                          | Field        | Used by                                            |
| ----------------------------- | ------------ | -------------------------------------------------- |
| `Service Account Auth Token`  | `credential` | the `onepassword-token` secret above               |
| `cloudflare`                  | `api-token`  | cert-manager DNS-01 (`ClusterIssuer`), via ExternalSecret |
| `talsecret-<cluster>`         | (document)   | disaster recovery only                             |

The `cloudflare` item needs a Cloudflare API token with **Zone → DNS → Edit** on
`cyseclab.net`.

## 8. Hand over to Argo

The Applications track `targetRevision: main` on GitHub, so **any local change
must be pushed before this step** — Argo reads the remote, not your working tree.

```sh
kubectl apply -f ../clusters/prod/root.yaml
kubectl -n argocd get applications -w
```

Argo adopts the Cilium and Argo CD releases installed above rather than replacing
them, which is the whole reason steps 6 and 7 use the same value files.

> [!TIP] Argo's initial admin password:
> ```sh
> kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath='{.data.password}' | base64 -d
> ```

## 9. DNS

Point a wildcard at the Gateway's address.
`10.42.5.240` is pinned via the `io.cilium/lb-ipam-ips` annotation on the Gateway, so this record never has to change.

```
*.lab.cyseclab.net.      A   10.42.5.240
*.dev.lab.cyseclab.net.  A   10.42.5.248
```

## Troubleshooting

**`kube-apiserver` crash-loops with `PodSecurity invalid: exemptions.namespaces[1]: Duplicate value: "kube-system"`**
Talos already ships `exemptions.namespaces: [kube-system]`, and machine config
patches **merge into** that list instead of replacing it, so naming `kube-system`
again in `talos/patches/pod-security.yaml` produces a duplicate the apiserver
rejects outright. The patch therefore sets `defaults` only and leaves `exemptions`
alone. Inspect the merged result with:

```sh
talosctl read /system/config/kubernetes/kube-apiserver/admission-control-config.yaml -n 10.42.5.201
```

**A fixed machine config is applied but the control plane does not recover**
Talos serves static pods to the kubelet over `staticPodURL` (so
`/etc/kubernetes/manifests` being empty is normal). If the apiserver has already
crash-looped into a long backoff it may not pick the new spec up. Confirm Talos
has the new revision, then restart the kubelet:

```sh
talosctl get staticpods -n 10.42.5.201          # VERSION should have incremented
talosctl service kubelet restart -n 10.42.5.201
```

**Nothing on `10.42.5.2xx` is reachable**
Check the Tailscale subnet route first (see the note in step 0) before suspecting
the nodes. `ssh pvelaptop` and run the check from the L2 to tell the two apart.
