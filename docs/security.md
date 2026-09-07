# Security <!-- omit in toc -->

- [Pod Security](#pod-security)
- [Network](#network)
  - [Where the policies live](#where-the-policies-live)
  - [What the policies do not cover](#what-the-policies-do-not-cover)
- [Secrets](#secrets)

## Pod Security

[Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) is set in two places:

**Cluster-wide default**: `talos/patches/pod-security.yaml`, applied to both clusters:

|              |              |
| ------------ | ------------ |
| `enforce`    | `baseline`   |
| `warn`       | `restricted` |
| `audit`      | `restricted` |

So anything worse than baseline is rejected outright, and anything short of `restricted` still gets a warning on apply and an entry in the audit log.

**Per namespace**: every Application that owns a namespace sets the same three labels through `managedNamespaceMetadata`, so the policy is visible next to the component rather than only in the machine config.
Namespace labels override the cluster default, which makes exceptions possible.

## Network

The cluster is default-deny.
`infrastructure/base/network-policies/default-deny.yaml` is a `CiliumClusterwideNetworkPolicy` selecting every endpoint in both
directions, so a pod with no policy of its own can send and receive nothing.
Everything that works, works because something granted it explicitly.

Two things are granted centrally, because every pod needs them:

| | |
| --- | --- |
| DNS | every pod may query CoreDNS, and nothing else, on port 53 |
| CoreDNS | answers the cluster, forwards to the Talos host resolver, watches Services |

### Where the policies live

| Component | Policy |
| --- | --- |
| the default-deny, DNS, CoreDNS | `infrastructure/base/network-policies/` |
| a platform component | `infrastructure/base/<component>/networkpolicy.yaml` |
| a workload | `apps/base/<app>/networkpolicy.yaml` |

### What the policies do not cover

- **Nodes themselves** `hostFirewall` is off, so policy applies to pods and not to the machines. Therefore, Talos's own attack surface is unchanged.
- **Encryption** Nothing here encrypts pod-to-pod traffic or node-to-node traffic.
- **Authentication** Nothing here authenticates the traffic. Identity is derived from labels, so anything that can get those labels onto a pod inherits the permissions.

## Secrets

External Secrets using 1Password, there is one vault and service account per cluster (`homelab-prod`, `homelab-dev`) so dev cannot read prod credentials.

Talos machine secrets are per cluster, held in 1Password as the `talsecret-prod` and `talsecret-dev` documents in the shared `HomeLab` vault.
`HomeLab` is outside both service account tokens, and each cluster's `ClusterSecretStore` is pinned to its own cluster vault, so no in-cluster identity can read a bundle.
Only OpenTofu reads them, from the operator workstation, through the operator's own 1Password session.
