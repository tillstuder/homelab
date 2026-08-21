#!/usr/bin/env python3
"""Flag Helm values keys the chart does not declare.

Helm silently ignores unknown values keys — a values file can be entirely wrong
and still render perfectly. Nothing at runtime reports this either: the setting
simply never takes effect. This is the one class of error neither `helm
template` nor the cluster will tell you about.

Usage: values_audit.py <declared.json> <ours.json> [<ours.json> ...]
All inputs are JSON (converted from YAML by yq in validate.sh).
"""
import json
import sys


# Some chart values are documented as accepting arbitrary user-supplied keys
# while *also* declaring defaults of their own. Helm's schema cannot express
# that, so they are listed here by hand.
FREEFORM = {
    ("configs", "params"),  # argo-cd: arbitrary argocd-cmd-params-cm entries
    ("configs", "cm"),      # argo-cd: arbitrary argocd-cm entries
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
    declared = json.load(open(sys.argv[1]))
    unknown = []
    for f in sys.argv[2:]:
        ours = json.load(open(f))
        for path in leaf_paths(ours):
            found, deepest = lookup(declared, path)
            if found:
                continue
            # A chart may declare a freeform map as `{}` or null and expect the
            # user to fill it in (argo-cd's `configs.repositories`, for example).
            # Anything under such a parent is legitimate.
            if deepest is None or (isinstance(deepest, dict) and not deepest):
                continue
            if any(path[:i] in FREEFORM for i in range(1, len(path))):
                continue
            unknown.append(".".join(path))
    for k in unknown:
        print(f"        {k}")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
