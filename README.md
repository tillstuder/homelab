# HomeLab

## Structure

The hierarchy is: _Cluster_ > _Namespace_ > _Application_ > _Component_

```text
.
├─ talos                            MACHINE LAYER
│  ├─ talconfig-<cluster>.yaml      talhelper
│  ├─ talenv.yaml                   Talos + Kubernetes versions
│  └─ patches                       shared machine config patches
│
├─ bootstrap                        BOOTSTRAPPING
│
├─ clusters                         WHAT EACH CLUSTER RUNS
│  └─ <cluster>
│     ├─ root.yaml                  app-of-apps root
│     ├─ projects.yaml              AppProjects
│     ├─ platform/*.yaml            one Application per platform component
│     ├─ apps/*.yaml                one Application per workload
│     └─ values/*.yaml              per-cluster Helm values
│
├─ infrastructure                   PLATFORM CONTENT
│  ├─ base/<app>/values.yaml        Helm values shared by both clusters
│  └─ <cluster>/<ns>/<app>/config   cluster-specific CRs
│
└─ apps                             WORKLOAD CONTENT
   ├─ base/<app>                    manifests shared by both clusters
   └─ <cluster>/<app>               kustomize overlay
```

### Applications manage components, not whole apps

An application is split into the components that make it up, each its own Argo `Application`.
Cilium, for example, is `cilium` (the chart) and `cilium-config` (the `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`).

This costs an extra file and buys two things: a component can be synced or suspended without disturbing the rest, and ordering between them is explicit.

### Ordering is by sync wave

Ordering is expressed with `argocd.argoproj.io/sync-wave`:

| Wave   | What                                                    |
| ------ | ------------------------------------------------------- |
| `-100` | `root`, AppProjects                                     |
| `-10`  | Cilium                                                  |
| `-9`   | Cilium config                                           |
| `-5`   | local-path-provisioner                                  |
| `0`    | cert-manager, External Secrets, Argo CD                 |
| `1`    | ClusterIssuers, ClusterSecretStore                      |
| `5`    | Envoy Gateway (ships the Gateway API CRDs)              |
| `6`    | GatewayClass, Gateway, wildcard Certificate, HTTP→HTTPS, Argo CD's HTTPRoute |
| `10`   | Workloads                                               |

### Helm values

Charts are pulled straight from upstream.
Values come from git through a multi-source Application:

```yaml
sources:
  - repoURL: https://github.com/tillstuder/homelab.git
    ref: values
  - repoURL: https://helm.cilium.io
    chart: cilium
    targetRevision: 1.19.4
    helm:
      ignoreMissingValueFiles: true
      valueFiles:
        - $values/infrastructure/base/cilium/values.yaml
        - $values/clusters/prod/values/cilium.yaml
```

Argo merges the two in order, so the per-cluster file only ever holds what actually differs.

## Promotion

`dev` and `prod` pin chart versions independently in their own `Application` files, and Renovate moves them:

- **dev**: automerged as soon as a release exists
- **prod**: a PR after the release has aged 7 days, merged manually
- **talos/**: never automerged, 14 day soak

So a version reaches `dev`, runs there, and only then gets offered to `prod`.

## Pod Security

Pod Security Admission is set in two places:

**Cluster-wide default**: `talos/patches/pod-security.yaml`, applied to both clusters:

|              |              |
| ------------ | ------------ |
| `enforce`    | `baseline`   |
| `warn`       | `restricted` |
| `audit`      | `restricted` |

So anything worse than baseline is rejected outright, and anything short of `restricted` still gets a warning on apply and an entry in the audit log.

**Per namespace**: every Application that owns a namespace sets the same three labels through `managedNamespaceMetadata`, so the policy is visible next to the component rather than only in the machine config.
Namespace labels override the cluster default, which makes exceptions possible.

## Validation

`./scripts/validate.sh` runs four passes, and CI runs it on every PR:

1. **kustomize**: every directory rendered, then `kubeconform`.
2. **helm**: every chart templated with the exact value files Argo will use, mirroring Argo's `--include-crds` and `ignoreMissingValueFiles`. Catches a chart version that does not exist, a mistyped `$values` path, and values that break rendering.
3. **values keys**: every key in our value files checked against `helm show values` for the pinned chart.
4. **bootstrap drift**: the chart versions hard-coded in [bootstrap](./bootstrap/README.md) must match the Applications, or Argo's first sync would fight the Helm release the bootstrap just created instead of adopting it.

## Secrets

External Secrets using 1Password, there is one vault and service account per cluster (`homelab-prod`, `homelab-dev`) so dev cannot read prod credentials.

Talos machine secrets are per cluster (`talos/talsecret-prod.yaml`, `talos/talsecret-dev.yaml`), gitignored, and stored in 1Password.

## Next

- **Monitoring**: Alloy, Loki, Grafana
- **Notifications**: Using ntfy, so for example a failed Argo sync is a push notification to my phone.
- **Backups**: The workload data on `local-path` is currently node-local and unreplicated.
- **Kubelet certificates**: `serverTLSBootstrap` is on, but nothing approves the
  `kubelet-serving` CSRs, so they must be approved by hand after every rotation or
  `kubectl logs`/`exec`/`top` break. Needs a `kubelet-csr-approver`.
- **Isolation**: Kata Containers or similar.
- **Virtual Machines**: KubeVirt
