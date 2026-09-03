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

echo "== bootstrap drift =="
# docs/bootstrap.md helm-installs cilium and argo-cd with explicit versions.
# They must match the Applications, or Argo's first sync would fight the release
# the bootstrap just created instead of adopting it.
for comp in cilium argo-cd; do
  want=$(yq -r '.spec.sources[] | select(.chart) | .targetRevision' "clusters/prod/platform/$comp.yaml")
  got=$(grep --color=never -A2 "helm install $comp" docs/bootstrap.md \
        | grep --color=never -o -- '--version [^ ]*' | awk '{print $2}' | head -1)
  if [ "$want" = "$got" ]; then printf '  ok    %-10s bootstrap=%s application=%s\n' "$comp" "$got" "$want"
  else printf '  FAIL  %-10s bootstrap=%s application=%s\n' "$comp" "${got:-<none>}" "$want"; FAIL=1; fi
done


echo
[ "$FAIL" -eq 0 ] && echo "all good" || echo "FAILURES ABOVE"
exit $FAIL
