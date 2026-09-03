#!/usr/bin/env bash

set -euo pipefail

ROLE="${ROLE:-OpenTofu}"
USER="${USER_ID:-opentofu@pve}"
TOKEN="${TOKEN_ID:-homelab}"

PRIVS="$(tr -d '\n ' <<'PRIV'
Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,
Sys.Audit,Sys.AccessNetwork,Sys.Console,Sys.Modify,
SDN.Audit,SDN.Use,
VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,
VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,
VM.Console,VM.Migrate,VM.PowerMgmt,VM.Snapshot,VM.GuestAgent.Audit
PRIV
)"

if pveum role list --output-format json | grep -q "\"${ROLE}\""; then
  pveum role modify "$ROLE" --privs "$PRIVS"
  echo "role   ${ROLE}: updated"
else
  pveum role add "$ROLE" --privs "$PRIVS"
  echo "role   ${ROLE}: created"
fi

if pveum user list --output-format json | grep -q "\"${USER}\""; then
  echo "user   ${USER}: exists"
else
  pveum user add "$USER" --comment "OpenTofu for homelab bootstrap"
  echo "user   ${USER}: created"
fi
pveum acl modify / --users "$USER" --roles "$ROLE"

if pveum user token list "$USER" --output-format json | grep -q "\"${TOKEN}\""; then
  echo "token  ${USER}!${TOKEN}: exists, not reissued"
else
  echo "token  ${USER}!${TOKEN}: created, store the value in 1Password now"
  pveum user token add "$USER" "$TOKEN" --privsep 1 --output-format json
fi
pveum acl modify / --tokens "${USER}!${TOKEN}" --roles "$ROLE"
