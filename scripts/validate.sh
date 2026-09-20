#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)
FAIL=0
export HELM_REPOSITORY_CONFIG="${TMPDIR:-/tmp}/homelab-helm/repositories.yaml"
export HELM_REPOSITORY_CACHE="${TMPDIR:-/tmp}/homelab-helm/cache"
mkdir -p "$(dirname "$HELM_REPOSITORY_CONFIG")"
WORK="${TMPDIR:-/tmp}/homelab-validate"
rm -rf "$WORK"; mkdir -p "$WORK"

have() {
  command -v "$1" >/dev/null && return 0
  if [ -n "${CI:-}" ]; then
    printf '  FAIL  %s not installed — CI install step missing?\n' "$1"; FAIL=1
  else
    printf '  skip  %s not installed\n' "$1"
  fi
  return 1
}

echo "== kustomize =="
HAVE_KUBECONFORM=0; have kubeconform && HAVE_KUBECONFORM=1
while read -r d; do
  if out=$(kubectl kustomize "$d" 2>&1); then
    printf '  ok    %s\n' "$d"
    if [ "$HAVE_KUBECONFORM" = 1 ]; then
      if ! echo "$out" | kubeconform -strict -ignore-missing-schemas -summary >/dev/null 2>&1; then
        printf '  SCHEMA %s\n' "$d"; FAIL=1
      fi
    fi
  else
    printf '  FAIL  %s\n%s\n' "$d" "$(echo "$out" | head -5 | sed 's/^/        /')"; FAIL=1
  fi
done < <(find . -name kustomization.yaml -not -path './.git/*' -print0 | xargs -0 -n1 dirname | sort)

echo "== helm =="
while read -r app; do
  yq -e '.spec.sources' "$app" >/dev/null 2>&1 || continue
  chart=$(yq -r '.spec.sources[] | select(.chart) | .chart' "$app")
  [ -z "$chart" ] && continue
  repo=$(yq -r '.spec.sources[] | select(.chart) | .repoURL' "$app")
  ver=$(yq -r '.spec.sources[] | select(.chart) | .targetRevision' "$app")
  ns=$(yq -r '.spec.destination.namespace' "$app")
  name=$(yq -r '.metadata.name' "$app")

  args=()
  while read -r vf; do
    [ -z "$vf" ] && continue
    f="${vf/\$values\//$ROOT/}"
    [ -f "$f" ] && args+=(-f "$f")   # mirrors ignoreMissingValueFiles
  done < <(yq -r '.spec.sources[] | select(.chart) | .helm.valueFiles[]?' "$app")

  # An http(s) repo goes through --repo; anything else is an OCI registry.
  if [[ "$repo" == http* ]]; then ref=("$chart" --repo "$repo")
  else ref=("oci://$repo/$chart"); fi

  # A chart with no values file of its own leaves `args` empty, and an empty
  # array is an *unset* variable to bash 3.2, which `set -u` then kills.
  if helm template "$name" "${ref[@]}" --version "$ver" --include-crds \
       -n "$ns" ${args[@]+"${args[@]}"} >/dev/null 2>"${TMPDIR:-/tmp}/helm.err"; then
    printf '  ok    %-22s %s@%s\n' "$name" "$chart" "$ver"
    # Stash coordinates so the values-key pass does not re-resolve them.
    printf '%s\t%s\t%s\t%s\t%s\n' "$(echo "$app" | cut -d/ -f2)" "$name" "${ref[*]}" "$ver" "${args[*]-}" >> "$WORK/charts.tsv"
  else
    printf '  FAIL  %-22s %s@%s\n%s\n' "$name" "$chart" "$ver" \
      "$(head -5 "${TMPDIR:-/tmp}/helm.err" | sed 's/^/        /')"; FAIL=1
  fi
done < <(find clusters -path '*/platform/*.yaml' -o -path '*/apps/*.yaml' | grep -v kustomization | sort)

echo "== values keys =="
# Helm ignores values keys a chart does not declare, so a wrong key renders
# perfectly and simply never takes effect. Neither `helm template` above nor the
# cluster will ever mention it. Compare our keys against `helm show values`.
sort -u "$WORK/charts.tsv" 2>/dev/null | while IFS=$'\t' read -r cluster name ref ver vfiles; do
  # shellcheck disable=SC2086
  helm show values $ref --version "$ver" 2>/dev/null \
    | yq -o=json > "$WORK/$name.declared.json" 2>/dev/null || continue
  ours=()
  for f in $vfiles; do
    [ "$f" = "-f" ] && continue
    j="$WORK/$cluster.$name.$(basename "$(dirname "$f")").json"
    yq -o=json "$f" > "$j" 2>/dev/null && ours+=("$j")
  done
  [ ${#ours[@]} -eq 0 ] && continue
  if out=$(./scripts/values_audit.py --chart "$name" "$WORK/$name.declared.json" "${ours[@]}"); then
    printf '  ok    %-5s %-22s all keys declared by the chart\n' "$cluster" "$name"
  else
    printf '  KEYS  %-5s %-22s not declared by %s@%s:\n%s\n' "$cluster" "$name" "$name" "$ver" "$out"
    echo fail >> "$WORK/failed"
  fi
done
[ -f "$WORK/failed" ] && FAIL=1

echo "== tofu =="
if have tofu; then
  VT="$WORK/tofu-validate"; mkdir -p "$VT"
  # talos/ comes along because the roots read talenv.yaml and patches/ from it.
  tar -cf - --exclude='.terraform' --exclude='terraform.tfstate*' \
            --exclude='.credentials' --exclude='.env' tofu talos | tar -xf - -C "$VT"

  for d in "$VT"/tofu/clusters/*/; do
    name=$(basename "$d")
    if ! out=$(tofu -chdir="$d" init -backend=false -input=false -no-color 2>&1); then
      printf '  FAIL  %-6s init\n%s\n' "$name" "$(echo "$out" | head -8 | sed 's/^/        /')"; FAIL=1
      continue
    fi
    if out=$(tofu -chdir="$d" validate -no-color 2>&1); then
      printf '  ok    %s\n' "$name"
    else
      printf '  FAIL  %-6s validate\n%s\n' "$name" "$(echo "$out" | head -8 | sed 's/^/        /')"; FAIL=1
    fi
  done
fi

echo "== alloy =="
# The Alloy config is a program, and nothing else here reads it: kustomize
# embeds it as an opaque string and Helm never sees it at all. A component
# reference that does not resolve renders and applies perfectly, then crash-loops
# in the cluster. `alloy validate` is the only thing that catches that here.
ALLOYDIR=infrastructure/base/alloy/config
if have alloy; then
  if out=$(alloy validate "$ALLOYDIR" 2>&1); then
    printf '  ok    %s\n' "$ALLOYDIR"
  else
    printf '  FAIL  %s\n%s\n' "$ALLOYDIR" "$(echo "$out" | head -12 | sed 's/^/        /')"; FAIL=1
  fi
  for f in "$ALLOYDIR"/*.alloy; do
    if diff -q "$f" <(alloy fmt "$f") >/dev/null 2>&1; then
      printf '  ok    %s is formatted\n' "$f"
    else
      printf '  FMT   %s is not canonical, run: alloy fmt -w %s\n' "$f" "$f"; FAIL=1
    fi
  done
fi

echo "== network policy =="
# The cluster-wide default-deny is the one object whose absence is invisible.
# If it stops being rendered, every workload keeps working, Argo still reports
# Synced/Healthy, and nothing anywhere goes red — the cluster is simply open
# again. It carries Prune=false so a running cluster keeps it even then, but a
# cluster rebuilt from a tree that lost the file would never have had it. So the
# presence and the *shape* of it are asserted here instead of being trusted.
NPDIR=infrastructure/base/network-policies
if ! deny=$(kubectl kustomize "$NPDIR" 2>/dev/null \
     | yq -e 'select(.kind=="CiliumClusterwideNetworkPolicy" and .metadata.name=="default-deny")' 2>/dev/null) \
   || [ -z "$deny" ]; then
  printf '  FAIL  %s renders no default-deny CiliumClusterwideNetworkPolicy\n' "$NPDIR"; FAIL=1
else
  bad=0
  # `fromEndpoints: []` is an empty selector list and matches nothing, which is
  # what makes this a deny. `[{}]` is a list holding the empty selector and
  # matches everything, which would turn the floor into a cluster-wide allow-all
  # that still looks exactly like a default-deny at a glance.
  for dir in ingress:fromEndpoints egress:toEndpoints; do
    d=${dir%%:*}; sel=${dir##*:}
    n=$(echo "$deny" | yq ".spec.${d}[0].${sel} | length" 2>/dev/null)
    if [ "$n" != "0" ]; then
      printf '  FAIL  default-deny .spec.%s[0].%s has %s entries, must be empty or it allows all\n' "$d" "$sel" "$n"; bad=1
    fi
  done
  if [ "$(echo "$deny" | yq '.spec.endpointSelector | length')" != "0" ]; then
    printf '  FAIL  default-deny .spec.endpointSelector must be {} so it selects every pod\n'; bad=1
  fi
  if [ "$(echo "$deny" | yq '.metadata.annotations."argocd.argoproj.io/sync-options"')" != "Prune=false" ]; then
    printf '  FAIL  default-deny is missing the Prune=false sync-option\n'; bad=1
  fi
  [ "$bad" -eq 0 ] && printf '  ok    default-deny renders, selects everything, allows nothing\n' || FAIL=1
fi

for c in dev prod; do
  if kubectl kustomize "clusters/$c/platform" 2>/dev/null \
     | yq -e 'select(.kind=="Application" and .spec.source.path=="'"$NPDIR"'")' >/dev/null 2>&1; then
    printf '  ok    %-5s syncs %s\n' "$c" "$NPDIR"
  else
    printf '  FAIL  %-5s has no Application pointing at %s\n' "$c" "$NPDIR"; FAIL=1
  fi
done

# argocd-repo-server is the only pod allowed out to the internet, and its
# toFQDNs list is a second copy of the AppProjects' sourceRepos. Adding a chart
# repo to a project without adding the host here fails that Application's next
# sync with a connection error, so the two are compared.
fq=$(yq -r 'select(.metadata.name=="argocd-repo-server") | .spec.egress[].toFQDNs[]? | (.matchName // .matchPattern)' \
      infrastructure/base/argo-cd/networkpolicy.yaml 2>/dev/null | grep -v '^---$')
for c in dev prod; do
  bad=0
  while read -r repo; do
    [ -z "$repo" ] && continue
    host=${repo#*://}; host=${host%%/*}
    # An OCI registry is reached at its registry endpoint, not at the bare name
    # the AppProject lists (docker.io -> registry-1.docker.io).
    [ "$host" = "docker.io" ] && host=registry-1.docker.io
    matched=0
    while read -r pat; do
      [ -z "$pat" ] && continue
      # shellcheck disable=SC2254  # glob match against matchPattern is intended
      case "$host" in $pat) matched=1; break ;; esac
    done < <(echo "$fq")
    if [ "$matched" -eq 0 ]; then
      printf '  FAIL  %-5s sourceRepo %s (%s) is not allowed by argocd-repo-server toFQDNs\n' "$c" "$repo" "$host"; bad=1
    fi
  done < <(yq -r '.spec.sourceRepos[]?' "clusters/$c/projects.yaml" | grep -v '^---$' | sort -u)
  [ "$bad" -eq 0 ] && printf '  ok    %-5s every sourceRepo host is in argocd-repo-server toFQDNs\n' "$c" || FAIL=1
done

# cert-manager's DNS-01 self-check bypasses CoreDNS, so it cannot be expressed
# as a toFQDNs rule and is pinned by CIDR instead. That CIDR list and the
# --dns01-recursive-nameservers flag have to name the same resolvers, or
# issuance hangs on "not yet propagated" with nothing else to show for it.
want=$(yq -r '.dns01RecursiveNameservers' infrastructure/base/cert-manager/values.yaml \
       | tr ',' '\n' | sed 's/:.*//' | grep -v '^$' | sort | tr '\n' ' ')
got=$(yq -r 'select(.metadata.name=="cert-manager") | .spec.egress[].toCIDR[]?' \
       infrastructure/base/cert-manager/networkpolicy.yaml | grep -v '^---$' | sed 's|/32$||' | sort | tr '\n' ' ')
if [ "$want" = "$got" ]; then
  printf '  ok    cert-manager DNS-01 resolvers match its egress CIDRs\n'
else
  printf '  FAIL  cert-manager DNS-01 resolvers disagree with its egress policy\n'
  printf '        values: %s\n        policy: %s\n' "$want" "$got"; FAIL=1
fi

echo "== prometheus reload =="
# Prometheus re-reads its ConfigMap only when something tells it to. The chart's
# Deployment carries no checksum of that ConfigMap, so Argo changing a rule
# leaves the running pod on its old config indefinitely while every Application
# still reports Synced and Healthy. The reloader sidecar and the /-/reload
# endpoint it POSTs to are therefore both load-bearing, and both are values a
# future edit could drop without anything going red.
for c in dev prod; do
  app="clusters/$c/platform/prometheus.yaml"
  [ -f "$app" ] || continue
  ver=$(yq -r '.spec.sources[] | select(.chart == "prometheus") | .targetRevision' "$app")
  args=()
  while read -r vf; do
    [ -z "$vf" ] && continue
    f="${vf/\$values\//$ROOT/}"
    [ -f "$f" ] && args+=(-f "$f")   # mirrors ignoreMissingValueFiles
  done < <(yq -r '.spec.sources[] | select(.chart == "prometheus") | .helm.valueFiles[]?' "$app")

  out=$(helm template prometheus prometheus \
          --repo https://prometheus-community.github.io/helm-charts \
          --version "$ver" -n monitoring ${args[@]+"${args[@]}"} 2>/dev/null)
  rules=$(echo "$out" \
          | yq -r 'select(.kind=="ConfigMap" and .metadata.name=="prometheus-server") | .data."alerting_rules.yml" // ""' 2>/dev/null \
          | grep -c -- '- alert:')
  if [ "${rules:-0}" -eq 0 ]; then
    printf '  ok    %-5s no alerting rules, nothing to reload\n' "$c"
    continue
  fi

  bad=0
  if ! echo "$out" | yq -r 'select(.kind=="Deployment" and .metadata.name=="prometheus-server") | .spec.template.spec.containers[].name' \
       | grep -q 'configmap-reload'; then
    printf '  FAIL  %-5s %s alerting rules but no configmap-reload sidecar — a rule change would never reach the pod\n' "$c" "$rules"; bad=1
  fi
  if ! echo "$out" | yq -r 'select(.kind=="Deployment" and .metadata.name=="prometheus-server") | .spec.template.spec.containers[] | select(.name=="prometheus-server") | .args[]' \
       | grep -q -- '--web.enable-lifecycle'; then
    printf '  FAIL  %-5s web.enable-lifecycle is not set, so /-/reload is disabled and the reloader cannot do anything\n' "$c"; bad=1
  fi
  [ "$bad" -eq 0 ] && printf '  ok    %-5s %s rules, reloader present and /-/reload enabled\n' "$c" "$rules" || FAIL=1
done

echo "== alerting =="
# The Slack ping is content-free on purpose, so its deep link is the only route
# from the notification to the alert. Nothing reports a broken one: Alertmanager
# renders an undefined template as the empty string, so a cluster missing its
# values file sends a "https://" link that still delivers, still returns 200 and
# still looks like a working alert. The host is therefore asserted here, against
# the hostname Grafana is actually routed on.
for c in dev prod; do
  app="clusters/$c/platform/alertmanager.yaml"
  [ -f "$app" ] || continue
  ver=$(yq -r '.spec.sources[] | select(.chart == "alertmanager") | .targetRevision' "$app")
  args=()
  while read -r vf; do
    [ -z "$vf" ] && continue
    f="${vf/\$values\//$ROOT/}"
    [ -f "$f" ] && args+=(-f "$f")   # mirrors ignoreMissingValueFiles
  done < <(yq -r '.spec.sources[] | select(.chart == "alertmanager") | .helm.valueFiles[]?' "$app")

  got=$(helm template alertmanager alertmanager \
          --repo https://prometheus-community.github.io/helm-charts \
          --version "$ver" -n monitoring ${args[@]+"${args[@]}"} 2>/dev/null \
        | yq -r 'select(.kind=="ConfigMap") | .data[]' 2>/dev/null \
        | sed -n 's/.*define "homelab.grafana" }}\(.*\){{ end }}.*/\1/p' | head -1)
  want=$(yq -r '.route.main.hostnames[0] // ""' "clusters/$c/values/grafana.yaml" 2>/dev/null)

  if [ -z "$got" ]; then
    printf '  FAIL  %-5s defines no homelab.grafana — the deep link would render as "https://"\n' "$c"; FAIL=1
  elif [ "$got" != "$want" ]; then
    printf '  FAIL  %-5s deep link points at %s, Grafana is routed on %s\n' "$c" "$got" "$want"; FAIL=1
  else
    printf '  ok    %-5s deep link matches the Grafana route (%s)\n' "$c" "$got"
  fi
done

echo "== approver allowlist =="
# kubelet-csr-approver decides which node names and IPs may hold a serving certificate,
# and it cannot read the tofu `nodes` map — the allowlist is a second copy of it. A node
# added to main.tf but not to the values file gets its CSR *denied*, which stays invisible
# until someone runs `kubectl logs` against that node. So the two are compared here, and
# adding a node without widening the allowlist fails the PR instead of the cluster.
for c in dev prod; do
  vals="clusters/$c/values/kubelet-csr-approver.yaml"
  main="tofu/clusters/$c/main.tf"
  if [ ! -f "$vals" ] || [ ! -f "$main" ]; then
    printf '  FAIL  %-5s %s or %s missing\n' "$c" "$vals" "$main"; FAIL=1; continue
  fi

  # `"prod-cp-1" = { vm_id = 201, ip = "10.42.5.201", ... }` -> `prod-cp-1 10.42.5.201`.
  # This assumes one node per line, which is how the map is written and how `tofu fmt`
  # keeps it. A node the parse drops still fails below as a missing IP, not silently.
  parsed=$(sed -n '/^  nodes = {/,/^  }/p' "$main" \
    | sed -nE 's/^[[:space:]]*"([^"]+)"[[:space:]]*=[[:space:]]*\{.*[[:space:]]ip[[:space:]]*=[[:space:]]*"([^"]+)".*/\1 \2/p')

  # A parse that silently matched nothing would report perfect agreement.
  if [ -z "$parsed" ]; then
    printf '  FAIL  %-5s no nodes parsed out of %s — has the map changed shape?\n' "$c" "$main"; FAIL=1; continue
  fi

  regex=$(yq -r '.providerRegex' "$vals")
  bad=0

  while read -r name _; do
    [ -z "$name" ] && continue
    if ! [[ $name =~ $regex ]]; then
      printf '  FAIL  %-5s node %s is not matched by providerRegex %s\n' "$c" "$name" "$regex"; bad=1
    fi
  done < <(echo "$parsed")

  want=$(echo "$parsed" | awk '{print $2"/32"}' | sort | tr '\n' ' ')
  got=$(yq -r '.providerIpPrefixes[]' "$vals" | sort | tr '\n' ' ')
  if [ "$want" != "$got" ]; then
    printf '  FAIL  %-5s providerIpPrefixes disagrees with %s\n' "$c" "$main"
    printf '        tofu:   %s\n        values: %s\n' "$want" "$got"; bad=1
  fi

  if [ "$bad" -eq 0 ]; then
    printf '  ok    %-5s %s node(s) match %s\n' "$c" "$(echo "$parsed" | wc -l | tr -d ' ')" "$main"
  else
    FAIL=1
  fi
done

echo
[ "$FAIL" -eq 0 ] && echo "all good" || echo "FAILURES ABOVE"
exit $FAIL
