# Bootstrap <!-- omit in toc -->

- [Prerequisites](#prerequisites)
  - [DNS](#dns)
  - [Secrets](#secrets)
    - [Cloudflare](#cloudflare)
    - [Talos](#talos)
    - [1Password Service Account Token](#1password-service-account-token)
    - [Grafana](#grafana)
    - [Argo CD](#argo-cd)
- [1. Create the Proxmox identity for OpenTofu](#1-create-the-proxmox-identity-for-opentofu)
- [2. Build the cluster](#2-build-the-cluster)
  - [Kubelet serving certificates](#kubelet-serving-certificates)
- [3. Install Cilium](#3-install-cilium)
- [4. Install Argo CD](#4-install-argo-cd)
- [5. Setup 1Password Token](#5-setup-1password-token)
- [6. Hand over to Argo](#6-hand-over-to-argo)

## Prerequisites

### DNS

You need a zone hosted with Cloudflare, named by `var.dns_zone` (default is `cyseclab.net`).
Everything below the zone, for example the per-cluster wildcard record, is created by OpenTofu.

If a cluster's record already exists, adopt it once (see [Day-2](./day-2.md#adopting-existing-dns-records)) or the first apply will try to create a duplicate.

### Secrets

You need a 1Password vault per cluster, so dev credentials and prod credentials never share the same blast radius:

```sh
op vault create homelab-prod
op vault create homelab-dev
```

Everything from here on uses `homelab-prod`. For the dev cluster, substitute `homelab-dev` and `talsecret-dev` throughout.

#### Cloudflare

To control Cloudflare, you need a `cloudflare` item which needs an API token with **Zone -> DNS -> Edit** and **Zone -> Zone -> Read** privileges on the zone.
You can easily create it from the `Edit zone DNS` template at https://dash.cloudflare.com/profile/api-tokens.

Once you have the token, store it in the cluster's vault as an **API Credential** item titled `cloudflare` with field `api-token`:

```sh
printf 'Cloudflare API token: '; read -rs CF_TOKEN; echo
op item create --category="API Credential" --title=cloudflare \
  --vault=homelab-prod "api-token=$CF_TOKEN"
unset CF_TOKEN
```

#### Talos

Next you need to create the Talos secrets bundle, its the cluster's root of trust:

```sh
talosctl gen secrets -o talsecret-prod.yaml
op document create talsecret-prod.yaml --title talsecret-prod --vault homelab-prod
rm talsecret-prod.yaml
```

#### 1Password Service Account Token

For your secrets to become accessible to Kubernetes, you need a 1Password Service Account Token.

Create one per cluster, scoped to that cluster's vault only, so a compromised dev cluster cannot read prod credentials:

```sh
op service-account create "homelab-prod" --vault "homelab-prod:read_items" --raw
```

Store the printed token in the cluster's vault as `Service Account Auth Token`:

```sh
printf '1Password Service Account Token: '; read -rs OP_TOKEN; echo
op item create --category="API Credential" --title="Service Account Auth Token" \
  --vault=homelab-prod "credential=$OP_TOKEN"
unset OP_TOKEN
```

> [!TIP]
> To revoke or rotate these tokens, visit:
> https://my.1password.com/developer-tools/active/service-accounts

#### Grafana

Grafana's admin account is created in the cluster's vault as `grafana`:

```sh
op item create --category=Login --title=grafana --vault=homelab-prod \
  --generate-password='letters,digits,symbols,32' username=admin
```

#### Argo CD

Argo CD's admin account works the same way, except that Argo stores the password bcrypt-hashed.
So the item carries both: `password` for you to log in with, `password-bcrypt` for the cluster:

```sh
op item create --category=Login --title=argocd --vault=homelab-prod \
  --generate-password='letters,digits,symbols,32' username=admin

op item edit argocd --vault=homelab-prod "password-bcrypt[password]=$(
  htpasswd -nbBC 10 '' "$(op read 'op://homelab-prod/argocd/password')" | tr -d ':\n' | sed 's/^\$2y/$2a/'
)"
```

## 1. Create the Proxmox identity for OpenTofu

Do this once per Proxmox host.

```sh
ssh pvesmall 'bash -s' < tofu/scripts/pve-identity.sh
```

Store the printed token in the cluster's vault as `proxmox-opentofu`:

> [!WARNING]
> You have to input the entire token including the prefix.
> e.g.: `opentofu@pve!homelab=xxxxxxxx-xxxx-...`

```sh
printf 'Proxmox API token (opentofu@pve!homelab=<uuid>): '; read -rs PVE_TOKEN; echo
op item create --category="API Credential" --title=proxmox-opentofu \
  --vault=homelab-prod "credential=$PVE_TOKEN"
unset PVE_TOKEN
```

## 2. Build the cluster

```sh
cd tofu/clusters/prod
cp .env.example .env
op run --env-file=.env -- tofu init
op run --env-file=.env -- tofu apply
```

After everything is done, the cluster credentials are written to `.credentials/`.
You can use them like this:

```sh
export TALOSCONFIG=$PWD/.credentials/talosconfig
export KUBECONFIG=$PWD/.credentials/kubeconfig
talosctl -n 10.42.5.201 etcd members
kubectl get nodes
```

> [!WARNING]
> Nodes stay `NotReady` until Cilium is installed.

Before proceeding, change your working directory to the repo root, so the relative paths resolve correctly:

```sh
cd ../../..
```

### Kubelet serving certificates

`talos/patches/kubelet.yaml` sets `serverTLSBootstrap: true`, so every kubelet requests a serving certificate through a CSR.

Until they are signed, `kubectl logs`, `exec` and `top` fail with `remote error: tls: internal error`.

`kubelet-csr-approver` will sign them automatically, but it is an Argo Application and Argo does not exist yet at this point.

So the CSRs stay `Pending` for the rest of the bootstrap, and get approved on their own after the handover to Argo.

They can be approved by hand if for example `kubectl logs` is needed before then:

```sh
kubectl get csr -o name --field-selector spec.signerName=kubernetes.io/kubelet-serving \
  | xargs -n1 kubectl certificate approve
```

## 3. Install Cilium

As a pre-requisite, we have to install the ServiceMonitor CRDs first:

```sh
grep -A1 'chart: prometheus-operator-crds' clusters/prod/platform/prometheus-operator-crds.yaml

helm install prometheus-operator-crds prometheus-operator-crds \
  --repo https://prometheus-community.github.io/helm-charts --version <from the grep above> \
  --namespace kube-system \
  -f infrastructure/base/prometheus-operator-crds/values.yaml
```

Now you can install Cilium with **the same value files Argo will use**, so the Application adopts the release later instead of fighting it:

```sh
grep -A1 'chart: cilium' clusters/prod/platform/cilium.yaml

helm install cilium cilium --repo https://helm.cilium.io --version --version <from the grep above>  \
  --namespace kube-system \
  -f infrastructure/base/cilium/values.yaml \
  -f clusters/prod/values/cilium.yaml
```

All nodes should reach `Ready` about a minute later.

## 4. Install Argo CD

Same approach, the value files the Application will later use:

```sh
grep -A1 'chart: argo-cd' clusters/prod/platform/argo-cd.yaml

helm install argo-cd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version <from the grep above> \
  --namespace argocd --create-namespace \
  -f infrastructure/base/argo-cd/values.yaml \
  -f clusters/prod/values/argo-cd.yaml
```

## 5. Setup 1Password Token

Hand the previously created 1Password Service Account Token to the cluster:

```sh
kubectl create namespace external-secrets
kubectl create secret generic onepassword-token \
  --namespace external-secrets \
  --from-literal=token="$(op read 'op://homelab-prod/Service Account Auth Token/credential')"
```

## 6. Hand over to Argo

```sh
kubectl apply -f clusters/prod/projects.yaml
kubectl apply -f clusters/prod/root.yaml
kubectl -n argocd get applications -w
```

Every Application should reach `Synced`/`Healthy`.

`cilium` stays `Progressing` while any node is down, because it is a DaemonSet.

Once `kubelet-csr-approver` is up, the kubelet CSRs left over from
[2. Build the cluster](#kubelet-serving-certificates) are approved within seconds:

```sh
kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving
```

All of them should read `Approved,Issued`, and `kubectl top nodes` should answer.

> [!TIP]
> Once `argo-cd-secret` has synced, the admin password is the one from the vault:
> ```sh
> op read 'op://homelab-prod/argocd/password'
> ```
> Until then, Argo is still on the password it generated for itself at install time:
> ```sh
> kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
> ```
>
> To access the UI, port-forward the service:
> ```sh
> kubectl port-forward service/argo-cd-argocd-server -n argocd 8080:443
> ```
> Then visit http://localhost:8080 and log in with username `admin` and the password from above.
