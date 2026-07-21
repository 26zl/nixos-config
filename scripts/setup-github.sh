#!/usr/bin/env bash
# GitHub CLI + git authentication. Run as your normal user (NO sudo):
#   bash scripts/setup-github.sh
set -euo pipefail

if gh auth status >/dev/null 2>&1; then
  echo "==> Already logged in to GitHub:"
  gh auth status
else
  echo "==> Logging in to GitHub via your web browser..."
  gh auth login --hostname github.com --git-protocol https --web
fi

echo "==> Wiring git <-> gh credentials"
gh auth setup-git

# Derive the global git identity from the GitHub account; fall back to the
# privacy-preserving noreply address when the account email is hidden.
login="$(gh api user --jq .login)"
name="$(gh api user --jq '.name // .login')"
id="$(gh api user --jq .id)"
email="$(gh api user --jq '.email // empty')"
[ -z "$email" ] && email="${id}+${login}@users.noreply.github.com"
git config --global user.name "$name"
git config --global user.email "$email"

git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true

echo
echo "DONE. git user.name=$(git config --global user.name)  user.email=$(git config --global user.email)"
