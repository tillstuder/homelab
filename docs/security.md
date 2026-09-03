# Security <!-- omit in toc -->

- [Pod Security](#pod-security)
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

## Secrets

External Secrets using 1Password, there is one vault and service account per cluster (`homelab-prod`, `homelab-dev`) so dev cannot read prod credentials.

Talos machine secrets are per cluster, held in 1Password as the `talsecret-prod` and `talsecret-dev` documents.
