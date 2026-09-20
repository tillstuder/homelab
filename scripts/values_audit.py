#!/usr/bin/env python3
"""Flag Helm values keys the chart does not declare.

Helm silently ignores unknown values keys — a values file can be entirely wrong
and still render perfectly. Nothing at runtime reports this either: the setting
simply never takes effect. This is the one class of error neither `helm
template` nor the cluster will tell you about.

Usage: values_audit.py [--chart <name>] <declared.json> <ours.json> [...]
All inputs are JSON (converted from YAML by yq in validate.sh).
"""

import json
import sys

# Some chart values are documented as accepting arbitrary user-supplied keys
# while *also* declaring defaults of their own. Helm's schema cannot express
# that, so they are listed here by hand, keyed by chart: `config` means the
# whole alertmanager.yml in one chart and a specific struct in another.
FREEFORM = {
    ("argo-cd", "configs", "params"),      # arbitrary argocd-cmd-params-cm entries
    ("argo-cd", "configs", "cm"),          # arbitrary argocd-cm entries
    ("grafana", "grafana.ini"),            # the whole grafana.ini, section by section
    ("loki", "loki", "limits_config"),     # any limit Loki itself accepts, not just the seeded ones
    ("alertmanager", "config"),            # the whole alertmanager.yml, defined by Alertmanager
    ("prometheus", "server", "global"),    # the prometheus.yml global block, defined by Prometheus
}


def leaf_paths(node, prefix=()):
    """Every leaf path in our values. Lists count as leaves — we never descend
    into list items, since charts declare them as empty defaults like `[]`."""
    if isinstance(node, dict) and node:
        for k, v in node.items():
            yield from leaf_paths(v, prefix + (k,))
    else:
        yield prefix


def lookup(declared, path):
    """Walk `path` through `declared`. Returns (found, deepest_existing_value)."""
    cur = declared
    for i, part in enumerate(path):
        if not isinstance(cur, dict) or part not in cur:
            return False, cur if i else declared
        cur = cur[part]
    return True, cur


def main():
    argv = sys.argv[1:]
    chart = None
    if argv[:1] == ["--chart"]:
        chart, argv = argv[1], argv[2:]
    with open(argv[0]) as fh:
        declared = json.load(fh)
    unknown = []
    for f in argv[1:]:
        with open(f) as fh:
            ours = json.load(fh)
        for path in leaf_paths(ours):
            found, deepest = lookup(declared, path)
            if found:
                continue
            # A chart may declare a freeform map as `{}` or null and expect the
            # user to fill it in (argo-cd's `configs.repositories`, for example).
            # Anything under such a parent is legitimate.
            if deepest is None or (isinstance(deepest, dict) and not deepest):
                continue
            if any((chart,) + path[:i] in FREEFORM for i in range(1, len(path) + 1)):
                continue
            unknown.append(".".join(path))
    for k in unknown:
        print(f"        {k}")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
