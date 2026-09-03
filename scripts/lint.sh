#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAIL=0
ALL=(yaml shell actions tofu python secrets)

have() {
  command -v "$1" >/dev/null && return 0
  if [ -n "${CI:-}" ]; then
    printf '  FAIL  %s not installed — CI install step missing?\n' "$1"; FAIL=1
  else
    printf '  skip  %s not installed\n' "$1"
  fi
  return 1
}

run() {
  local label=$1; shift
  local out
  if out=$("$@" 2>&1); then
    printf '  ok    %s\n' "$label"
  else
    # shellcheck disable=SC2001  # per-line indent, not a substring swap
    printf '  FAIL  %s\n%s\n' "$label" "$(echo "$out" | sed 's/^/        /')"; FAIL=1
  fi
}

check_yaml() {
  echo "== yaml =="
  have yamllint || return 0
  # -f github annotates the PR diff, so let that output through unfiltered.
  if [ -n "${CI:-}" ]; then yamllint -f github . || FAIL=1
  else run yamllint yamllint .; fi
}

check_shell() {
  echo "== shell =="
  have shellcheck || return 0
  run shellcheck shellcheck scripts/*.sh tofu/scripts/*.sh
}

check_actions() {
  echo "== actions =="
  have actionlint || return 0
  run actionlint actionlint
}

check_tofu() {
  echo "== tofu =="
  have tofu && run fmt tofu fmt -check -recursive tofu
  have tflint || return 0
  # .tflint.hcl sets call_module_type = "local": with no module manifest
  # installed tflint cannot see across a module call, so each directory is
  # linted in isolation and validate.sh owns the root -> module boundary.
  for d in tofu/modules/*/ tofu/clusters/*/; do
    run "tflint ${d%/}" tflint --chdir="$d" --config="$PWD/.tflint.hcl" --no-color
  done
}

check_python() {
  echo "== python =="
  have ruff || return 0
  if [ -n "${CI:-}" ]; then ruff check --output-format=github || FAIL=1
  else run ruff ruff check; fi
}

check_secrets() {
  echo "== secrets =="
  have gitleaks || return 0
  run gitleaks gitleaks git . --redact --no-banner
}

[ $# -eq 0 ] && set -- "${ALL[@]}"
for c in "$@"; do
  case "$c" in
    yaml)    check_yaml    ;;
    shell)   check_shell   ;;
    actions) check_actions ;;
    tofu)    check_tofu    ;;
    python)  check_python  ;;
    secrets) check_secrets ;;
    *) echo "unknown check: $c (have: ${ALL[*]})" >&2; exit 2 ;;
  esac
done

echo
[ "$FAIL" -eq 0 ] && echo "all good" || echo "FAILURES ABOVE"
exit $FAIL
