#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

for path in hosts.yml .env private.key secrets/token .vscode/settings.json; do
  git -C "$repo" check-ignore --quiet --no-index -- "$path" || fail "$path is not ignored"
done

for workflow in check.yml secret-scan.yml shellcheck.yml; do
  grep -Fq 'branches: ["**"]' "$repo/.github/workflows/$workflow" ||
    fail "$workflow does not cover branch names containing slashes"
  grep -Fq 'persist-credentials: false' "$repo/.github/workflows/$workflow" ||
    fail "$workflow persists the checkout credential"
done

if grep -Eq '^[[:space:]]+paths:' "$repo/.github/workflows/shellcheck.yml"; then
  fail "ShellCheck is still path-filtered and cannot reliably reactivate"
fi

grep -Fq 'bash tests/audit-regressions.sh' "$repo/.github/workflows/check.yml" ||
  fail "CI does not run the regression tests"
grep -Fq 'nix flake check --print-build-logs' "$repo/.github/workflows/check.yml" ||
  fail "CI does not run flake checks"
expected_precommit='pre-commit = preCommit;'
grep -Fq "$expected_precommit" "$repo/flake.nix" ||
  fail "the pre-commit checks are not exposed through nix flake check"
grep -Fq '9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c' \
  "$repo/.github/workflows/secret-scan.yml" ||
  fail "the Gitleaks archive checksum is not pinned"
grep -Fq 'fetch-depth: 0' "$repo/.github/workflows/secret-scan.yml" ||
  fail "the secret scan does not fetch full history"
grep -Fq './gitleaks git .' "$repo/.github/workflows/secret-scan.yml" ||
  fail "Gitleaks does not scan Git history"
expected_sbctl_package='packages.${system}.sbctl = pkgs.sbctl;'
grep -Fq "$expected_sbctl_package" "$repo/flake.nix" ||
  fail "sbctl is not exposed from the locked flake"
expected_sbctl_shell='shell "${REPO}#sbctl"'
grep -Fq "$expected_sbctl_shell" "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not use the locked sbctl package"
if grep -Fq '>hardware-configuration.nix' "$repo/scripts/bootstrap.sh"; then
  fail "bootstrap truncates the active hardware configuration during generation"
fi
expected_hardware_tmp='mktemp "$REPO/hardware-configuration.nix.XXXXXX"'
grep -Fq "$expected_hardware_tmp" "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not stage generated hardware configuration"
expected_hardware_move='mv -- "$hardware_tmp" "$REPO/hardware-configuration.nix"'
grep -Fq "$expected_hardware_move" \
  "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not replace hardware configuration atomically"
grep -Fq 'command -v direnv >/dev/null; and direnv hook fish | source' \
  "$repo/dotfiles/config.fish" ||
  fail "Fish does not activate direnv"
grep -Fq 'shell fish' "$repo/dotfiles/kitty.conf" ||
  fail "Kitty uses a non-portable shell path"
if grep -Fq '/run/current-system/sw/bin/fish' "$repo/dotfiles/kitty.conf"; then
  fail "Kitty still contains the NixOS-only shell path"
fi
grep -Fq '[hostname]' "$repo/dotfiles/starship.toml" ||
  fail "Starship does not configure its hostname module"
grep -Fq 'ssh_only = false' "$repo/dotfiles/starship.toml" ||
  fail "Starship hides the hostname outside SSH"
if grep -Fq '"Containments/1/Wallpaper' "$repo/home.nix"; then
  fail "Home Manager writes a fragile Plasma containment ID"
fi
grep -Fq '"net.ipv6.conf.default.use_tempaddr" = 2;' "$repo/hardening.nix" ||
  fail "new interfaces do not inherit IPv6 privacy addressing"
grep -Fq 'sudo bash scripts/bootstrap.sh' "$repo/README.md" ||
  fail "the quick start bypasses the Secure Boot bootstrap"
grep -Fq 'clone https://github.com/26zl/nixos-config ~/Desktop/nixos-config' "$repo/README.md" ||
  fail "the documented clone path disagrees with programs.nh.flake"
if grep -Fq 'sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix' \
  "$repo/README.md"; then
  fail "the quick start duplicates and bypasses bootstrap logic"
fi
if grep -Fq 'cd /etc/nixos && sudo nix flake update' "$repo/README.md"; then
  fail "the update instructions mutate the deployment mirror"
fi
if grep -Eq '^sudo nix-collect-garbage -d' "$repo/README.md"; then
  fail "the cleanup instructions delete the documented rollback history"
fi
grep -Fq 'does not back up' "$repo/README.md" ||
  fail "the documentation does not disclose the backup boundary"

expected_filter='--exclude-from="$REPO/.gitignore"'
grep -Fq -- "$expected_filter" "$repo/scripts/apply.sh" ||
  fail "apply.sh does not exclude ignored files from the deployment mirror"
expected_realpath='realpath "${BASH_SOURCE[0]}"'
grep -Fq "$expected_realpath" "$repo/scripts/apply.sh" ||
  fail "apply.sh does not resolve symlinked launch paths"

guard_line="$(grep -n 'EUID -ne 0' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
sync_line="$(grep -n '^rsync ' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1)"
if [[ -z $guard_line || $guard_line -ge $sync_line ]]; then
  fail "apply.sh does not reject non-root execution before mirroring"
fi
trap_line="$(grep -n 'trap finish_deploy EXIT' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
if [[ -z $trap_line || $trap_line -ge $sync_line ]]; then
  fail "apply.sh does not establish recovery before mirroring"
fi
grep -Fq "trap 'exit 130' INT" "$repo/scripts/apply.sh" ||
  fail "apply.sh does not recover from interactive interruption"
grep -Fq "trap 'exit 143' TERM" "$repo/scripts/apply.sh" ||
  fail "apply.sh does not recover from termination"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/source/secrets" "$fixture/source/.vscode" "$fixture/destination"
touch \
  "$fixture/source/flake.nix" \
  "$fixture/source/hosts.yml" \
  "$fixture/source/.env" \
  "$fixture/source/private.key" \
  "$fixture/source/secrets/token" \
  "$fixture/source/.vscode/settings.json"

rsync -a --exclude=".git" --exclude-from="$repo/.gitignore" \
  "$fixture/source/" "$fixture/destination/"

[[ -f "$fixture/destination/flake.nix" ]] || fail "regular configuration was not mirrored"
for path in hosts.yml .env private.key secrets/token .vscode/settings.json; do
  [[ ! -e "$fixture/destination/$path" ]] || fail "$path was mirrored"
done

rollback_source="$fixture/rollback-source"
rollback_destination="$fixture/rollback-destination"
mock_bin="$fixture/mock-bin"
mkdir -p "$rollback_source/scripts" "$rollback_destination" "$mock_bin"
cp "$repo/.gitignore" "$rollback_source/.gitignore"
touch "$rollback_source/flake.nix" "$rollback_source/configuration.nix" "$rollback_source/managed.nix"
touch "$rollback_destination/pre-existing.nix"

destination_rewrite='s|^DST="/etc/nixos"$|DST="$TEST_DST"|'
sed \
  -e '/EUID -ne 0/s/.*/if false; then/' \
  -e "$destination_rewrite" \
  -e 's/ --chown=root:root//' \
  "$repo/scripts/apply.sh" >"$rollback_source/scripts/apply.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$mock_bin/nixos-rebuild"
chmod +x "$mock_bin/nixos-rebuild"

if TEST_DST="$rollback_destination" PATH="$mock_bin:$PATH" \
  bash "$rollback_source/scripts/apply.sh" >/dev/null 2>&1; then
  fail "the rollback fixture unexpectedly succeeded"
fi

[[ -f "$rollback_destination/pre-existing.nix" ]] ||
  fail "rollback did not restore the pre-existing destination"
[[ ! -e "$rollback_destination/managed.nix" ]] ||
  fail "rollback left mirrored files in the destination"
[[ ! -d "$rollback_destination/.git" ]] ||
  fail "rollback did not restore the original Git state"

mock_parent_signal='kill -TERM "$PPID"'
printf '%s\n' '#!/usr/bin/env bash' "$mock_parent_signal" 'sleep 0.1' 'exit 143' \
  >"$mock_bin/nixos-rebuild"
chmod +x "$mock_bin/nixos-rebuild"
if TEST_DST="$rollback_destination" PATH="$mock_bin:$PATH" \
  bash "$rollback_source/scripts/apply.sh" >/dev/null 2>&1; then
  fail "the interrupted rollback fixture unexpectedly succeeded"
fi

[[ -f "$rollback_destination/pre-existing.nix" ]] ||
  fail "interrupted deploy did not restore the pre-existing destination"
[[ ! -e "$rollback_destination/managed.nix" ]] ||
  fail "interrupted deploy left mirrored files in the destination"
[[ ! -d "$rollback_destination/.git" ]] ||
  fail "interrupted deploy did not restore the original Git state"

if ((failures > 0)); then
  exit 1
fi

echo "All audit regression tests passed."
