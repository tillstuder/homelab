# HomeLab <!-- omit in toc -->

## Structure

The hierarchy is: _Cluster_ > _Namespace_ > _Application_ > _Component_

```text
.
├─ tofu                             MACHINE LAYER
│  ├─ modules/talos-cluster         Proxmox VMs + Talos config + bootstrap
│  ├─ clusters/<cluster>            one root module and one state file each
│  └─ scripts                       the Proxmox identity OpenTofu runs as
│
├─ talos                            MACHINE CONFIG INPUTS
│  ├─ talenv.yaml                   Talos + Kubernetes versions
│  └─ patches                       shared machine config patches
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

## ToDos

- **Monitoring**: Alloy, Loki, Grafana
- **Notifications**: So for example a failed Argo sync is a push notification to my phone.
- **Backups**: The workload data on `local-path` is currently node-local and unreplicated.
- **App Authentication Layer**: Using Envoy Gateway with a OIDC Provider.
- **SAST and DAST Scanning**: Trivy, SonarQube, OWASP ZAP, etc.
- **Zero Trust Networking**: TODO
- **Security Review & Hardening** Talos, Kubernetes, ArgoCD, Envoy Gateway, etc.
- **OS Isolation**: Kata Containers or similar.
- **Virtual Machines**: KubeVirt
- **Allow spreading of Talos nodes across physical hosts**: e.g.:
  ```hcl
  nodes = {
    "prod-cp-1" = { vm_id = 201, ip = "10.42.5.201", pve_node = "pvebig" }
    "prod-cp-2" = { vm_id = 202, ip = "10.42.5.202", pve_node = "pvesmall" }
    "prod-cp-3" = { vm_id = 203, ip = "10.42.5.203", pve_node = "pvelaptop" }
  }
  ```
- x
