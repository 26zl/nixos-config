#!/usr/bin/env bash
# Bootstrap this configuration on a fresh NixOS install.
#
# Generates a hardware profile for THIS machine, then builds the system from the
# flake. Run from the repository root:
#
#   sudo bash scripts/bootstrap.sh
#
# For a machine other than the author's, also edit the user/host values called
# out in the README ("Adapt it to your machine") before or right after the first
# build.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script needs root. Re-run: sudo bash scripts/bootstrap.sh" >&2
  exit 1
fi

# Resolve the repo root from this script's location (works from anywhere).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if [[ ! -f flake.nix ]]; then
  echo "flake.nix not found in $REPO — run this from the cloned repository." >&2
  exit 1
fi

FLAKES=(--option extra-experimental-features 'nix-command flakes')

echo "==> Generating hardware-configuration.nix for this machine"
nixos-generate-config --show-hardware-config >hardware-configuration.nix

# Secure Boot (secureboot.nix) signs the boot chain, so signing keys must exist
# before the first build. Harmless if you later comment out the import to opt out.
if [[ ! -d /var/lib/sbctl/keys ]]; then
  echo "==> Creating Secure Boot signing keys (/var/lib/sbctl)"
  nix "${FLAKES[@]}" shell nixpkgs#sbctl -c sbctl create-keys
fi

echo "==> Building and switching to the new system"
nixos-rebuild switch --flake "${REPO}#nixos" "${FLAKES[@]}"

echo "==> Done. Reboot to land on the new generation cleanly."
echo "    Secure Boot: finish enrollment in the firmware — see README 'Secure Boot'."
