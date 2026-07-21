#!/usr/bin/env bash
# Deploy this whole config to /etc/nixos and rebuild. Run as root:
#   sudo bash scripts/apply.sh
#
# The repo is mirrored to /etc/nixos and committed there BEFORE building, so
# nixos-rebuild always sees a clean tree (no "Git tree is dirty"). A failed build
# rolls the deploy commit back.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DST="/etc/nixos"
gitx() {
  git -C "$DST" -c safe.directory="$DST" \
    -c user.email="deploy@localhost" -c user.name="nixos-deploy" "$@"
}

echo "==> Mirroring repo -> $DST"
mkdir -p "$DST"
rsync -a --delete --chown=root:root --exclude=".git" "$REPO/" "$DST/"

[ -d "$DST/.git" ] || gitx init -q -b main
prev="$(gitx rev-parse --verify -q HEAD || true)"
gitx add -A
if gitx diff --cached --quiet; then
  echo "==> No changes to commit"
  committed=false
else
  gitx commit -q -m "deploy $(date '+%Y-%m-%d %H:%M')"
  committed=true
fi

rollback() {
  [ "${committed:-false}" = true ] || return 0
  echo "==> Build failed — rolling back the deploy commit"
  if [ -n "$prev" ]; then gitx reset -q --hard "$prev"; else gitx update-ref -d HEAD; fi
}
trap rollback ERR

echo "==> Validating (dry-build; nothing is applied yet)"
nixos-rebuild dry-build --flake "$DST#nixos"

echo "==> Switching"
nixos-rebuild switch --flake "$DST#nixos"

trap - ERR
echo "==> Done — /etc/nixos committed and clean. Reboot if kernel params changed."
