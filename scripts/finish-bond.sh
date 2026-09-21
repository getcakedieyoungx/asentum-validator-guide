#!/usr/bin/env bash
# finish-bond.sh — finish an Asentum validator install that got stuck.
#
# Use when the official installer:
#   - hangs at "Syncing blockchain … 99%" (pull-mode nodes trail the
#     finalized head by ~20 blocks, so its sync gate never passes), or
#   - fails at bond with "insufficient balance for value plus gas"
#     (its 1 ASE gas buffer is too small).
#
# What it does: downloads the OFFICIAL installer, runs only its post-sync
# steps (read address, back up key, faucet, bond) and raises the bond
# gas buffer to 10 ASE. It does not re-download the snapshot or touch
# your chain data or validator.key.
#
# Run ONCE, as root, on a validator that is NOT bonded yet.
set -euo pipefail

PRIMARY=${ASENTUM_PRIMARY:-https://testnet.asentum.com}
INSTALL_DIR=/opt/asentum/install
HELPER="$INSTALL_DIR/bond-helper.mjs"

die() { printf '\033[33m✗\033[0m %s\n' "$*" >&2; exit 1; }
say() { printf '\033[32m‣\033[0m %s\n' "$*"; }

[[ $EUID -eq 0 ]] || die "Run as root."
systemctl is-active --quiet asentum-validator \
  || die "asentum-validator service is not running. Run the official installer first."
[[ -f /opt/asentum/data/validator.key ]] \
  || die "No validator.key found. Run the official installer first."

if command -v asentum-validator >/dev/null; then
  STAKE=$(asentum-validator status 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' \
    | awk '/bonded stake/ {print $3}')
  if [[ -n "${STAKE:-}" && "$STAKE" != "0" ]]; then
    die "This validator already has $STAKE ASE bonded. Nothing to do."
  fi
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

say "Downloading official installer + bond helper…"
curl -fsSL "$PRIMARY/install/validator" -o "$TMP/install.sh"
mkdir -p "$INSTALL_DIR"
curl -fsSL "$PRIMARY/install/bond-helper.mjs" -o "$HELPER"

say "Raising bond gas buffer 1 → 10 ASE…"
sed -i 's/const GAS_BUFFER_WEI = 1n \* 10n \*\* 18n;/const GAS_BUFFER_WEI = 10n * 10n ** 18n;/' "$HELPER"
if grep -q 'GAS_BUFFER_WEI = 10n' "$HELPER"; then
  echo "  patched"
else
  echo "  (upstream helper changed. Using it as-is.)"
fi

# Official installer = [config + helpers] + banner + [pre-sync] + [post-sync].
# Keep config/helpers, skip everything up to "Read validator address".
awk '/^banner$/{exit} {print}' "$TMP/install.sh" >  "$TMP/post-sync.sh"
awk '/Read validator address/{p=1} p'  "$TMP/install.sh" >> "$TMP/post-sync.sh"
grep -q 'bond-helper.mjs' "$TMP/post-sync.sh" \
  || die "Official installer layout changed. Aborting without changes."
bash -n "$TMP/post-sync.sh" || die "Extracted script failed syntax check. Aborting."

say "Running official post-sync steps (address → key backup → faucet → bond)…"
bash "$TMP/post-sync.sh"
