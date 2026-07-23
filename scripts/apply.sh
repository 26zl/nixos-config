#!/usr/bin/env bash
# Deploy this whole config to /etc/nixos and rebuild. Run as root:
#   sudo bash scripts/apply.sh
#
# The repo is mirrored to /etc/nixos and committed there before building.
# Any deploy error restores the complete pre-deploy destination snapshot.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script needs root. Re-run: sudo bash scripts/apply.sh" >&2
  exit 1
fi

script_path="$(realpath "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$script_path")/.." && pwd)"
DST="/etc/nixos"
if [[ $REPO == "/" || $REPO == "$DST" || -L $DST || ! -f "$REPO/flake.nix" ||
  ! -f "$REPO/configuration.nix" || ! -f "$REPO/.gitignore" ]]; then
  echo "Refusing to deploy from invalid source: $REPO" >&2
  exit 1
fi

gitx() {
  git -C "$DST" -c safe.directory="$DST" \
    -c user.email="deploy@localhost" -c user.name="nixos-deploy" "$@"
}

backup="$(mktemp -d /var/tmp/nixos-config-backup.XXXXXX)"
destination_existed=false
deploy_mutated=false
deploy_succeeded=false
if [[ -d $DST ]]; then
  destination_existed=true
fi

cleanup_backup() {
  rm -rf -- "$backup"
}
restore_destination() {
  if [[ $destination_existed == true ]]; then
    mkdir -p "$DST"
    rsync -a --delete "$backup/" "$DST/"
  else
    rm -rf -- "$DST"
  fi
}
finish_deploy() {
  local exit_code=$?
  local recovery_ok=true
  trap - EXIT HUP INT TERM
  if [[ $deploy_mutated == true && $deploy_succeeded != true ]]; then
    echo "==> Deploy failed — restoring the previous $DST snapshot" >&2
    if ! restore_destination; then
      recovery_ok=false
    fi
  fi
  if [[ $recovery_ok == true ]]; then
    cleanup_backup
  else
    echo "Recovery failed; the snapshot remains at $backup" >&2
  fi
  exit "$exit_code"
}
trap finish_deploy EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $destination_existed == true ]]; then
  rsync -a "$DST/" "$backup/"
fi

echo "==> Mirroring repo -> $DST"
deploy_mutated=true
mkdir -p "$DST"
rsync -a --delete --chown=root:root --exclude=".git" \
  --exclude-from="$REPO/.gitignore" "$REPO/" "$DST/"

[ -d "$DST/.git" ] || gitx init -q -b main
gitx add -A
if gitx diff --cached --quiet; then
  echo "==> No changes to commit"
else
  gitx commit -q -m "deploy $(date '+%Y-%m-%d %H:%M')"
fi

echo "==> Validating (dry-build; nothing is applied yet)"
nixos-rebuild dry-build --flake "$DST#nixos"

echo "==> Switching"
nixos-rebuild switch --flake "$DST#nixos"

deploy_succeeded=true
echo "==> Done — /etc/nixos committed and clean. Reboot if kernel params changed."
