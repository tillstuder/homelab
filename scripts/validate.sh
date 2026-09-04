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

  if helm template "$name" "${ref[@]}" --version "$ver" --include-crds \
       -n "$ns" "${args[@]}" >/dev/null 2>"${TMPDIR:-/tmp}/helm.err"; then
    printf '  ok    %-22s %s@%s\n' "$name" "$chart" "$ver"
    # Stash coordinates so the values-key pass does not re-resolve them.
    printf '%s\t%s\t%s\t%s\t%s\n' "$(echo "$app" | cut -d/ -f2)" "$name" "${ref[*]}" "$ver" "${args[*]}" >> "$WORK/charts.tsv"
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
  if out=$(./scripts/values_audit.py "$WORK/$name.declared.json" "${ours[@]}"); then
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
