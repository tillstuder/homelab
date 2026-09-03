# Architecture <!-- omit in toc -->

- [Applications manage components, not whole apps](#applications-manage-components-not-whole-apps)
- [Ordering is by sync wave](#ordering-is-by-sync-wave)
- [Helm values](#helm-values)
- [Promotion](#promotion)

## Applications manage components, not whole apps

An application is split into the components that make it up, each its own Argo `Application`.
Cilium, for example, is `cilium` (the chart) and `cilium-config` (the `CiliumLoadBalancerIPPool` and `CiliumL2AnnouncementPolicy`).

This costs an extra file and buys two things: a component can be synced or suspended without disturbing the rest and ordering between them is explicit.

## Ordering is by sync wave

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

## Helm values

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

`dev` and `prod` pin chart versions independently in their own `Application` files and Renovate moves them:

- **dev**: automerged as soon as a release exists
- **prod**: a PR after the release has aged 7 days, merged manually
- **talos/**: never automerged, 14 day soak
