# Security policy

This is a personal NixOS configuration, published so that others can reuse
it. It has no releases and no support team, but reports are welcome and taken
seriously: the point of `hardening.nix`, `secureboot.nix` and the bootstrap
scripts is that a machine ends up safer, not less safe.

## What to report

- A hardening claim that does not hold: a sysctl, kernel parameter, firewall
  rule, AppArmor, DNS or VPN setting in `hardening.nix` or `hardware.nix` that
  does not do what its comment or the README says, or that a nixpkgs change
  has silently undone.
- `scripts/bootstrap.sh` or `scripts/apply.sh` doing something unsafe as root:
  writing a host file from unescaped input, copying `.git` or git-ignored
  secrets into `/etc/nixos` or the Nix store, or leaving Secure Boot keys
  unprotected.
- A weakness in the GitHub Actions workflows, for example a way for a pull
  request to run with write permissions or to change `flake.lock` unnoticed.
- A secret, a host directory or another machine identifier committed to the
  repository or its history.

Vulnerabilities in NixOS, nixpkgs or the pinned inputs belong upstream.
`vulnix --system`, installed by `hardening.nix`, lists the known CVEs in the
running closure, and the weekly `Update flake.lock` workflow refreshes the
inputs once the updated closures build.

## How to report

Use GitHub private vulnerability reporting:
[open a draft security advisory](https://github.com/26zl/nixos-config/security/advisories/new).
Do not open a public issue for something exploitable. Ordinary bugs, such as a
build failure or a wrong default, go in a normal
[issue](https://github.com/26zl/nixos-config/issues).

Include the commit you ran, the relevant settings from your host file (the
values, not the directory itself, which holds machine identifiers) and how to
reproduce or verify the problem, for example a `sysctl` or `nft list ruleset`
excerpt.

## Supported versions

There are no releases. `main` is the supported version and tracks
`nixos-unstable` through `flake.lock`. A fix lands on `main`, and a machine
picks it up with `git pull` followed by `sudo bash scripts/apply.sh`.

## What to expect

One person maintains this repository, so there is no guaranteed response
time; reports are read and answered as soon as possible. A confirmed problem
is fixed on `main`, covered by `tests/audit-regressions.sh` where a regression
test is possible, and the advisory is published afterwards, crediting you if
you want that.
