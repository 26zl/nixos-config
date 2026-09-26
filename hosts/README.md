# Hosts

One directory per machine, created by `scripts/bootstrap.sh <host>`:

- `host.nix` — account, CPU, GPUs, form factor, Windows, locale, stateVersion
  (the settings and their defaults are listed in `lib/host.nix`)
- `hardware-configuration.nix` — generated: disks, filesystems, kernel modules

The directories are git-ignored. They hold the account name, disk UUIDs and
locale of a real machine, which do not belong in a public repository, and the
scripts read them through a `path:` flake reference, so they never need to be
tracked. `examples/` shows what the files look like for several kinds of
machines. To version your own hosts anyway, keep a private fork and add them
with `git add -f hosts/<name>`.
