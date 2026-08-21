# Bootstrap

Both `prod` and `dev` follow the same steps, please substitute the cluster name and, where noted, the differing IP.

`10.42.5.20-.199` is the DHCP range, so everything assigned here sits in `.200-.254`.

|            | prod                 | dev                    |
| ---------- | -------------------- | ---------------------- |
| Endpoint   | `10.42.5.200`        | `10.42.5.210`          |
| Nodes      | `.201` `.202` `.203` | `.210`                 |
| LB pool    | `10.42.5.240-.247`   | `10.42.5.248-.251`     |
| Gateway IP | `10.42.5.240`        | `10.42.5.248`          |
| Domain     | `lab.cyseclab.net`   | `dev.lab.cyseclab.net` |
| 1P vault   | `homelab-prod`       | `homelab-dev`          |

## 1. Proxmox VMs

Create the VMs and boot the Talos ISO.
Nothing here is managed by this repo, Talos is immutable, so the VM only needs a disk, a NIC on the `10.42.5.0/24` bridge, and enough RAM (prod nodes: 4 GB+, dev: 8 GB since it runs alone).

Then confirm the disk and NIC names the machine config will reference:

```sh
talosctl disks     -n 10.42.5.201 --insecure
talosctl get links -n 10.42.5.201 --insecure
```

Fix `installDisk` and `networkInterfaces[].deviceSelector` in `talos/talconfig-<cluster>.yaml` if they differ from the defaults.

## 2. Machine secrets

```sh
cd talos
talhelper gensecret > talsecret.yaml
op document create talsecret.yaml --title "talsecret-prod" --vault homelab-prod
```

## 3. Generate and apply machine configs

```sh
talhelper genconfig --config-file talconfig-prod.yaml --env-file talenv.yaml
talosctl apply-config --insecure -n 10.42.5.201 -f clusterconfig/prod-prod-cp-1.yaml
# repeat for each node...
```

## 4. Bring up the cluster

```sh
export TALOSCONFIG=./clusterconfig/talosconfig
talosctl config endpoint 10.42.5.201
talosctl config node     10.42.5.201
talosctl bootstrap # only once, on a single control-plane node
talosctl kubeconfig .
```

Nodes stay `NotReady` until step 5, that is expected, as there is no CNI yet.

## 5. Cilium

Talos ships with `cniConfig: none` and kube-proxy disabled, so nothing networks until Cilium is installed. This is a one-shot install using **the same value files Argo will use**, so the Application adopts it cleanly instead of fighting it.

```sh
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.1 \
  --namespace kube-system \
  -f ../infrastructure/base/cilium/values.yaml \
  -f ../clusters/prod/values/cilium.yaml
```

## 6. Argo CD, and the 1Password token

Same trick, install with the value files the Application will later use.

```sh
helm install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version 10.4.0 \
  --namespace argocd --create-namespace \
  -f ../infrastructure/base/argo-cd/values.yaml \
  -f ../clusters/prod/values/argo-cd.yaml
```

The ClusterSecretStore authenticates with a 1Password service account token.

Create it before Argo syncs External Secrets, so the store is valid the first time it reconciles:

```sh
kubectl create namespace external-secrets
kubectl create secret generic onepassword-token \
  --namespace external-secrets \
  --from-literal=token="$(op read 'op://homelab-prod/Service Account Auth Token/credential')"
```

Note the vault differs per cluster: `homelab-prod` and `homelab-dev` have separate service accounts, so a wiped or compromised dev cluster cannot read prod credentials.

## 7. Hand over to Argo

```sh
kubectl apply -f ../clusters/prod/root.yaml
# ...
kubectl -n argocd get applications -w
```

> [!TIP] Argo's initial admin password:
> ```sh
> kubectl -n argocd get secret argocd-initial-admin-secret \
>   -o jsonpath='{.data.password}' | base64 -d
> ```

## 8. DNS

Point a wildcard at the Gateway's address.
`10.42.5.240` is pinned via the `io.cilium/lb-ipam-ips` annotation on the Gateway, so this record never has to change.

```
*.lab.cyseclab.net.      A   10.42.5.240
*.dev.lab.cyseclab.net.  A   10.42.5.248
```
