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

script_path="$(realpath "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$script_path")/.." && pwd)"
cd "$REPO"

if [[ ! -f flake.nix ]]; then
  echo "flake.nix not found in $REPO — run this from the cloned repository." >&2
  exit 1
fi

FLAKES=(--option extra-experimental-features 'nix-command flakes')

echo "==> Generating hardware-configuration.nix for this machine"
hardware_tmp="$(mktemp "$REPO/hardware-configuration.nix.XXXXXX")"
cleanup_hardware_tmp() {
  rm -f -- "$hardware_tmp"
}
trap cleanup_hardware_tmp EXIT
nixos-generate-config --show-hardware-config >"$hardware_tmp"
if [[ ! -s "$hardware_tmp" ]]; then
  echo "Generated hardware configuration is empty; keeping the existing file." >&2
  exit 1
fi
if [[ -e "$REPO/hardware-configuration.nix" ]]; then
  chown --reference="$REPO/hardware-configuration.nix" "$hardware_tmp"
  chmod --reference="$REPO/hardware-configuration.nix" "$hardware_tmp"
else
  chmod 0644 "$hardware_tmp"
fi
mv -- "$hardware_tmp" "$REPO/hardware-configuration.nix"
trap - EXIT

# Secure Boot (secureboot.nix) signs the boot chain, so signing keys must exist
# before the first build. Harmless if you later comment out the import to opt out.
if [[ ! -d /var/lib/sbctl/keys ]]; then
  echo "==> Creating Secure Boot signing keys (/var/lib/sbctl)"
  nix "${FLAKES[@]}" shell "${REPO}#sbctl" -c sbctl create-keys
fi

echo "==> Building and switching to the new system"
nixos-rebuild switch --flake "${REPO}#nixos" "${FLAKES[@]}"

echo "==> Done. Reboot to land on the new generation cleanly."
echo "    Secure Boot: finish enrollment in the firmware — see README 'Secure Boot'."
