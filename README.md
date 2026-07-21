# ❄️ NixOS Config — ThinkPad T14 Gen 3 · KDE Plasma 6

A flake-based NixOS configuration for a Lenovo ThinkPad T14 Gen 3 (Intel,
dual-boot with Windows). Clean, reproducible, and hardened for daily use — built
to be forked: clone it, point it at your hardware and username, and rebuild.

## Highlights

- **Desktop:** KDE Plasma 6 (Wayland) + SDDM, PipeWire, Norwegian locale/keyboard,
  Plasma ⇄ browser integration for Chrome & Firefox, KDE Connect, fingerprint login
- **Look:** Nord (arctic blue-grey) — `nordic` Plasma/Kvantum/GTK theme, Nordzy icons
  & cursor; kitty, starship and fastfetch all themed to match
- **Terminal:** kitty running fish (login shell stays bash for KDE stability), starship
  prompt, a modern CLI (ripgrep, fd, bat, eza, fzf, zoxide, yazi, delta, fastfetch)
- **Dev:** VS Code + Neovim, curated language toolchains (Python / Node / Rust / Go /
  Java / C++) with language servers, `direnv` + `nix-direnv` for per-project shells,
  `gh` + GitHub Desktop + `lazygit`, DBeaver, Bruno, Ollama (local LLM), android-tools
- **Containers & VMs:** Docker, Podman, libvirt + virt-manager
- **System engineering:** kubectl/k9s/helm/kubectx, OpenTofu, lazydocker/dive, sops+age,
  Ansible; a Neovim config (Lua) with LSP for bash/yaml/docker/ansible/terraform/nix
- **Security tooling:** Wireshark, nmap, tcpdump, Burp Suite, Lynis, ClamAV, auditd
  (Sysmon-style kernel audit logging), KeePassXC; Mullvad + Tailscale + WireGuard
- **Apps:** Chrome, Discord, VLC/mpv, LibreOffice, Thunderbird, EasyEffects
- **Laptop:** power-profiles-daemon, Intel VAAPI hardware video acceleration, fwupd
  (firmware/BIOS updates), zram swap
- **Security & privacy** (`hardening.nix`): kernel/boot hardening, Madaidan-aligned
  sysctls, kernel-module blacklist, locked root account, disabled core dumps,
  Wi-Fi MAC privacy, encrypted DNS (opportunistic DNS-over-TLS with Quad9 fallback),
  Mullvad VPN, AppArmor, firewall — a _desktop-safe_ subset tuned to NOT break KDE,
  Docker, VMs or dev tooling
- **Declarative dotfiles + KDE:** Home Manager manages the shell/terminal/Neovim dotfiles,
  and plasma-manager applies the Nord global theme automatically (no System Settings clicks)
- **Dual-boot friendly:** systemd-boot (auto-detects Windows), local-time RTC

## Layout

| Path                         | Purpose                                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------------------- |
| `flake.nix` / `flake.lock`   | Flake entry point; pins nixpkgs (unstable)                                                              |
| `configuration.nix`          | Main system configuration                                                                               |
| `hardening.nix`              | Security & privacy hardening (imported by `configuration.nix`)                                          |
| `hardware-configuration.nix` | Machine-specific (disks/drivers) — regenerate on other hardware                                         |
| `dotfiles/`                  | `bashrc`, `config.fish`, `kitty.conf`, `starship.toml`, `fastfetch.jsonc`, `direnvrc` (all Nord-themed) |
| `scripts/bootstrap.sh`       | Fresh-install setup: generate hardware profile, first build                                             |
| `scripts/apply.sh`           | Deploy to `/etc/nixos`, validate, rebuild                                                               |
| `scripts/setup-github.sh`    | Authenticate git + gh                                                                                   |
| `.github/workflows/`         | CI: flake evaluation, ShellCheck, Gitleaks secret scan                                                  |

## Quick start (fresh NixOS install)

From a freshly installed NixOS, one command clones the repo, generates a
hardware profile for **your** machine, and builds the system:

```sh
nix --extra-experimental-features 'nix-command flakes' run nixpkgs#git -- \
  clone https://github.com/26zl/nixos-config ~/nixos-config \
  && cd ~/nixos-config \
  && sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix \
  && sudo nixos-rebuild switch --flake .#nixos \
       --option extra-experimental-features 'nix-command flakes'
```

The same steps live in [`scripts/bootstrap.sh`](scripts/bootstrap.sh) if you have
already cloned the repo:

```sh
sudo bash scripts/bootstrap.sh
```

> Regenerating `hardware-configuration.nix` is important: it captures **your**
> disks, filesystems and drivers. The copy committed here belongs to the author's
> machine and will not match yours.

> **Secure Boot is enabled** in this config. Before the first build, either create
> signing keys (`sudo nix-shell -p sbctl --run 'sbctl create-keys'` — see
> [Secure Boot](#secure-boot)) or comment out the `./secureboot.nix` import in
> `configuration.nix` to skip it. Otherwise the first `switch` fails at bootloader
> signing.

## Adapt it to your machine

Before building, change the few values that are specific to a user/host:

| Where               | Change                                                                           |
| ------------------- | -------------------------------------------------------------------------------- |
| `home.nix`          | `home.username` / `home.homeDirectory` → your user                               |
| `configuration.nix` | `users.users.<name>`, `programs.nh.flake` path, `time.timeZone`, locale/keyboard |
| `flake.nix`         | `users.<name> = import ./home.nix;` → your user                                  |

Everything else (theme, tooling, hardening) is host-agnostic and works as-is.

## Day-to-day

**Apply local edits** — after changing any file in this repo:

```sh
sudo bash scripts/apply.sh     # copies the repo into /etc/nixos, validates, rebuilds
```

**Update the whole system** — refresh all flake inputs (nixpkgs, home-manager, …)
and rebuild onto the new versions:

```sh
cd /etc/nixos && sudo nix flake update && sudo nixos-rebuild switch --flake .#nixos
# or, with the nh helper shipped in this config:
nh os switch --update        # update inputs + rebuild in one step
```

**Clean up** — reclaim disk by deleting old generations and deduplicating the store:

```sh
nh clean all --keep 5        # keep the last 5 generations, GC the rest
sudo nix-collect-garbage -d  # (equivalent) delete all old generations
sudo nix store optimise      # hard-link identical files to save space
```

Old boot entries disappear from the menu after the next rebuild following a cleanup.

**Roll back** if a rebuild misbehaves — pick an older generation in the boot menu, or:

```sh
sudo nixos-rebuild switch --rollback
```

## Secure Boot

Secure Boot is **enabled** via [lanzaboote](https://github.com/nix-community/lanzaboote):
`configuration.nix` imports `./secureboot.nix`, which signs the whole boot chain.
A machine without signing keys fails at bootloader install, so a fresh install must
**create keys first** — or opt out by commenting the `./secureboot.nix` import.

One-time setup (ThinkPad instructions; keeps the Windows dual-boot working):

```sh
# 1. Create signing keys (written to /var/lib/sbctl)
sudo nix-shell -p sbctl --run 'sbctl create-keys'
```

2. Build (the `./secureboot.nix` import is already active) and confirm signing:

```sh
sudo bash scripts/apply.sh
sudo sbctl verify   # BOOTX64.EFI + generation EFIs show ✓ (bzImage / Microsoft / fallback lines are expected unsigned)
```

3. Reboot → **Reboot into Firmware** → _Security → Secure Boot_: set **Secure
   Boot = enabled**, then **Reset to Setup Mode**, and press **F10** to save.
   (Do _not_ pick "Clear All Secure Boot Keys".)

4. Back in NixOS, enroll your keys together with Microsoft's (so Windows and
   signed option-ROMs still boot):

```sh
sudo sbctl enroll-keys --microsoft
```

If it reports `File is immutable` on KEK/db, clear the flag and retry:

```sh
sudo chattr -i /sys/firmware/efi/efivars/KEK-* /sys/firmware/efi/efivars/db-*
sudo sbctl enroll-keys --microsoft
```

5. Reboot and confirm:

```sh
bootctl status      # Secure Boot: enabled (user)
```

To opt out entirely: comment the `./secureboot.nix` import in `configuration.nix`,
rebuild, and disable Secure Boot in the firmware. Full runbook also lives in
`secureboot.nix`.

## Dotfiles on other systems

On this NixOS host, Home Manager applies every dotfile and the **Nord** KDE look
declaratively — no manual copying. To reuse the shell/terminal/Neovim configs on
another distro (Fedora, etc.) or Windows, copy them straight from `dotfiles/`:

```sh
cp dotfiles/bashrc ~/.bashrc
cp dotfiles/starship.toml ~/.config/starship.toml
mkdir -p ~/.config/direnv && cp dotfiles/direnvrc ~/.config/direnv/direnvrc
mkdir -p ~/.config/kitty ~/.config/fish ~/.config/fastfetch ~/.config/nvim
cp dotfiles/kitty.conf ~/.config/kitty/kitty.conf
cp dotfiles/config.fish ~/.config/fish/config.fish
cp dotfiles/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
cp dotfiles/nvim/init.lua ~/.config/nvim/init.lua
```

The Neovim config (lazy.nvim + LSP via `vim.lsp.enable`, Nord theme) installs its
plugins on first `nvim` launch; on NixOS the language servers come from the system,
elsewhere from Mason. On a non-Nix desktop, apply the Nord look manually in System
Settings → Appearance: Colors (Nordic) · Icons (Papirus-Dark) · Cursors (Nordzy).

## Post-install notes

- **Fingerprint:** enroll in System Settings → Users (Synaptics reader).
- **Mullvad:** open the Mullvad VPN app and sign in with your account number.
- **Flathub:** `flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo`
- **Prompt font:** set Konsole's font to _JetBrainsMono Nerd Font_ so the starship
  theme's icons render.
- **Battery:** set a charge limit (~80%) in System Settings → Power Management.

## Credits / inspiration

The hardening and several structure ideas were distilled — and adapted to a
**desktop-safe** posture — from these community projects. Thanks to their authors:

- **NixOS hardening framework** (© 2026 Elaina) — the security/privacy baseline that
  `hardening.nix` is distilled from
- **[ryan4yin/nix-config](https://github.com/ryan4yin/nix-config)** (Ryan Yin) — Nix
  settings & structure
- **[mitchellh/nixos-config](https://github.com/mitchellh/nixos-config)** (Mitchell
  Hashimoto) — configuration-structure reference
- **[Athena-OS/athena-nix](https://github.com/Athena-OS/athena-nix)** — security /
  pentesting tooling reference
- **[mikeroyal/NixOS-Guide](https://github.com/mikeroyal/NixOS-Guide)** — general reference
- **[26zl/fedora-44-kde-setup](https://github.com/26zl/fedora-44-kde-setup)** — starship
  theme, shell aliases, VPN-aware resolved settings, and the CI workflow patterns

## Notes

- `hardware-configuration.nix` contains machine identifiers (disk UUIDs), not secrets.
- **No credentials, tokens, SSH keys, or private data are committed** — enforced by
  `.gitignore` and the Gitleaks CI workflow.
- Claude Code is installed via its own self-updating native installer (runs thanks to
  `programs.nix-ld`), not as a Nix package — so it stays current independently.

## License

[MIT](LICENSE)
