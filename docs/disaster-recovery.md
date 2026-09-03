# Disaster recovery <!-- omit in toc -->

- [Lost the local credentials](#lost-the-local-credentials)
- [Lost a node](#lost-a-node)

## Lost the local credentials

```sh
cd tofu/clusters/prod
op run --env-file=.env -- tofu apply -replace='module.cluster.terraform_data.credentials[0]'
```

> [!NOTE]
> Bumping `credentials_revision` in the root module does the same thing declaratively, which is the better move if you want the reason recorded in git.

## Lost a node

Evict it from etcd before destroying it, or the remaining members keep counting it toward quorum:

```sh
talosctl -n 10.42.5.203 etcd remove-member prod-cp-3
op run --env-file=.env -- tofu apply
```
