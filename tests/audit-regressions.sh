#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

for path in hosts.yml .env private.key secrets/token .vscode/settings.json hosts/somebox/host.nix; do
  git -C "$repo" check-ignore --quiet --no-index -- "$path" || fail "$path is not ignored"
done
if git -C "$repo" check-ignore --quiet --no-index -- hosts/README.md; then
  fail "hosts/README.md is ignored, so a clone would have no hosts/ directory for the flake to read"
fi
[[ -f "$repo/hosts/README.md" ]] || fail "hosts/README.md is missing"

for workflow in check.yml secret-scan.yml shellcheck.yml; do
  grep -Fq 'branches: ["**"]' "$repo/.github/workflows/$workflow" ||
    fail "$workflow does not cover branch names containing slashes"
  grep -Fq 'cancel-in-progress: true' "$repo/.github/workflows/$workflow" ||
    fail "$workflow keeps running after a newer commit supersedes it"
done

for workflow in check.yml secret-scan.yml shellcheck.yml update-flake-lock.yml; do
  grep -Fq 'persist-credentials: false' "$repo/.github/workflows/$workflow" ||
    fail "$workflow persists the checkout credential"
  grep -Eq '^[[:space:]]+concurrency:|^concurrency:' "$repo/.github/workflows/$workflow" ||
    fail "$workflow does not serialise its runs"
  grep -Eq '^[[:space:]]+timeout-minutes:' "$repo/.github/workflows/$workflow" ||
    fail "$workflow can hang for the runner's six-hour default"
done

if grep -Eq '^[[:space:]]+paths:' "$repo/.github/workflows/shellcheck.yml"; then
  fail "ShellCheck is still path-filtered and cannot reliably reactivate"
fi

grep -Fq 'bash tests/audit-regressions.sh' "$repo/.github/workflows/check.yml" ||
  fail "CI does not run the regression tests"
grep -Fq '"example-${name}"' "$repo/flake.nix" ||
  fail "the example systems are not exposed as flake checks"
grep -Fq '"toplevel-${name}"' "$repo/flake.nix" ||
  fail "local hosts are not exposed as flake checks"
grep -Fq 'checks.x86_64-linux.example-${{ matrix.host }}' "$repo/.github/workflows/check.yml" ||
  fail "CI only evaluates the example hosts and never builds them"
grep -Fq 'fromJSON(needs.quality.outputs.examples)' "$repo/.github/workflows/check.yml" ||
  fail "the build matrix is not derived from the example files"
grep -Fq '.#checks.x86_64-linux.formatting' "$repo/.github/workflows/check.yml" ||
  fail "CI does not run the formatting check"
grep -Fq '.#checks.x86_64-linux.pre-commit' "$repo/.github/workflows/check.yml" ||
  fail "CI does not run the pre-commit checks"
grep -Fq 'example-hosts' "$repo/flake.nix" ||
  fail "the example hosts are not evaluated as a flake check"
grep -Fq '.#checks.x86_64-linux.example-hosts' "$repo/.github/workflows/check.yml" ||
  fail "CI does not evaluate the example hosts"

# Every example host file is a host file rather than a stray module, and the
# stand-in hardware configuration they share exists.
for example in "$repo"/examples/*.nix; do
  [[ ${example##*/} == hardware-configuration.nix ]] && continue
  grep -Eq '^[[:space:]]+user = "' "$example" || fail "${example#"$repo"/} does not set a user"
  grep -Eq '^[[:space:]]+stateVersion = "' "$example" || fail "${example#"$repo"/} does not set stateVersion"
done
[[ -f "$repo/examples/hardware-configuration.nix" ]] ||
  fail "the example hosts have no stand-in hardware configuration"

# The lock-file update is only trustworthy if the closures are realised before
# the pull request exists; a pull request opened first would carry no evidence.
lock_workflow="$repo/.github/workflows/update-flake-lock.yml"
build_line="$(grep -n '#checks.x86_64-linux.example-' "$lock_workflow" | head -n 1 | cut -d: -f1 || true)"
pr_line="$(grep -n 'peter-evans/create-pull-request' "$lock_workflow" | head -n 1 | cut -d: -f1 || true)"
if [[ -z $build_line || -z $pr_line || $build_line -ge $pr_line ]]; then
  fail "the flake update opens a pull request without first building the closures"
fi

for invariant in \
  'config.boot.lanzaboote.enable && !config.boot.loader.systemd-boot.enable' \
  'config.networking.firewall.enable' \
  'config.security.sudo.wheelNeedsPassword'; do
  grep -Fq "assertion = $invariant;" "$repo/configuration.nix" ||
    fail "the system no longer asserts: $invariant"
done
grep -Fq 'system.stateVersion = host.stateVersion;' "$repo/configuration.nix" ||
  fail "stateVersion is no longer taken from the host file"
grep -Fq 'flake = "path:${host.flakePath}";' "$repo/configuration.nix" ||
  fail "nh reads the clone through git and would not see the ignored host directory"

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
expected_hardware_tmp='mktemp "$host_dir/hardware-configuration.nix.XXXXXX"'
grep -Fq "$expected_hardware_tmp" "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not stage generated hardware configuration"
expected_hardware_move='mv -- "$hardware_tmp" "$host_dir/hardware-configuration.nix"'
grep -Fq "$expected_hardware_move" \
  "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not replace hardware configuration atomically"
grep -Fq 'flakePath = "$REPO";' "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap does not record the clone path for programs.nh"
grep -Fq -- '--flake "path:${REPO}#${HOST}"' "$repo/scripts/bootstrap.sh" ||
  fail "bootstrap builds through git, which cannot see the ignored host directory"
if grep -Eq 'git .*add' "$repo/scripts/bootstrap.sh"; then
  fail "bootstrap stages the host directory, which would put a real machine into the public repository"
fi
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
grep -Fq 'name = "nixos-wallpaper.png";' "$repo/home.nix" ||
  fail "the wallpaper is referenced inside the flake source and dies on garbage collection"
grep -Fq '"net.ipv6.conf.default.use_tempaddr" = lib.mkForce 2;' "$repo/hardening.nix" ||
  fail "new interfaces do not inherit IPv6 privacy addressing"
grep -Fq 'sudo bash scripts/bootstrap.sh' "$repo/README.md" ||
  fail "the quick start bypasses the Secure Boot bootstrap"
grep -Fq 'git-ignored' "$repo/README.md" ||
  fail "the README does not say that host directories stay out of the repository"
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
grep -Fq -- '--include="/hosts/***"' "$repo/scripts/apply.sh" ||
  fail "apply.sh drops the ignored host directories from the mirror"
include_line="$(grep -n -- '--include="/hosts/\*\*\*"' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
exclude_line="$(grep -n -- '--exclude-from="$REPO/.gitignore"' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
if [[ -z $include_line || -z $exclude_line || $include_line -gt $exclude_line ]]; then
  fail "apply.sh applies the .gitignore exclusions before the hosts include, so rsync drops the hosts"
fi
grep -Fq 'gitx add -A -f' "$repo/scripts/apply.sh" ||
  fail "the deployment mirror's git repository skips the ignored host directory"
grep -Fq -- '--flake "path:$DST#$HOST"' "$repo/scripts/apply.sh" ||
  fail "apply.sh builds through git, which cannot see the ignored host directory"
expected_realpath='realpath "${BASH_SOURCE[0]}"'
grep -Fq "$expected_realpath" "$repo/scripts/apply.sh" ||
  fail "apply.sh does not resolve symlinked launch paths"

guard_line="$(grep -n 'EUID -ne 0' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
sync_line="$(grep -n '^rsync ' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1)"
if [[ -z $guard_line || $guard_line -ge $sync_line ]]; then
  fail "apply.sh does not reject non-root execution before mirroring"
fi
host_line="$(grep -n 'hosts/$HOST/host.nix' "$repo/scripts/apply.sh" | head -n 1 | cut -d: -f1 || true)"
if [[ -z $host_line || $host_line -ge $sync_line ]]; then
  fail "apply.sh mirrors before checking that the host exists"
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
mkdir -p "$fixture/source/secrets" "$fixture/source/.vscode" "$fixture/source/hosts/somebox" "$fixture/destination"
cp "$repo/.gitignore" "$fixture/source/.gitignore"
touch \
  "$fixture/source/flake.nix" \
  "$fixture/source/hosts.yml" \
  "$fixture/source/.env" \
  "$fixture/source/private.key" \
  "$fixture/source/secrets/token" \
  "$fixture/source/.vscode/settings.json" \
  "$fixture/source/hosts/somebox/host.nix"

# the same filter apply.sh uses: ignored files stay out, ignored host directories go in
rsync -a --exclude=".git" --include="/hosts/***" --exclude-from="$repo/.gitignore" \
  "$fixture/source/" "$fixture/destination/"

[[ -f "$fixture/destination/flake.nix" ]] || fail "regular configuration was not mirrored"
[[ -f "$fixture/destination/hosts/somebox/host.nix" ]] || fail "the ignored host directory was not mirrored"
for path in hosts.yml .env private.key secrets/token .vscode/settings.json; do
  [[ ! -e "$fixture/destination/$path" ]] || fail "$path was mirrored"
done

rollback_source="$fixture/rollback-source"
rollback_destination="$fixture/rollback-destination"
mock_bin="$fixture/mock-bin"
mkdir -p "$rollback_source/scripts" "$rollback_source/hosts/testhost" "$rollback_destination" "$mock_bin"
cp "$repo/.gitignore" "$rollback_source/.gitignore"
touch "$rollback_source/flake.nix" "$rollback_source/configuration.nix" "$rollback_source/managed.nix" \
  "$rollback_source/hosts/testhost/host.nix" "$rollback_source/hosts/testhost/hardware-configuration.nix"
touch "$rollback_destination/pre-existing.nix"

destination_rewrite='s|^DST="/etc/nixos"$|DST="$TEST_DST"|'
sed \
  -e '/EUID -ne 0/s/.*/if false; then/' \
  -e "$destination_rewrite" \
  -e 's/ --chown=root:root//' \
  "$repo/scripts/apply.sh" >"$rollback_source/scripts/apply.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$mock_bin/nixos-rebuild"
chmod +x "$mock_bin/nixos-rebuild"

# An unknown host is refused before anything is mirrored.
if TEST_DST="$rollback_destination" PATH="$mock_bin:$PATH" \
  bash "$rollback_source/scripts/apply.sh" no-such-host >/dev/null 2>&1; then
  fail "apply.sh accepted a host that has no host.nix"
fi
[[ ! -e "$rollback_destination/managed.nix" ]] ||
  fail "apply.sh mirrored the repo for a host that does not exist"

if TEST_DST="$rollback_destination" PATH="$mock_bin:$PATH" \
  bash "$rollback_source/scripts/apply.sh" testhost >/dev/null 2>&1; then
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
  bash "$rollback_source/scripts/apply.sh" testhost >/dev/null 2>&1; then
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
