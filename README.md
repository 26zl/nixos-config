# ❄️ NixOS Config — ThinkPad T14 Gen 3 · KDE Plasma 6

A flake-pinned NixOS configuration for a Lenovo ThinkPad T14 Gen 3 (Intel,
dual-boot with Windows), hardened for daily use and designed to be forked.

## Highlights

- **Desktop:** KDE Plasma 6 (Wayland) + SDDM, PipeWire, Norwegian locale/keyboard,
  Plasma browser integration for Chrome and Firefox, KDE Connect, fingerprint login
- **Look:** Nord (arctic blue-grey) — `nordic` Plasma/Kvantum/GTK theme, Nordzy icons
  & cursor; kitty, starship and fastfetch all themed to match
- **Terminal:** kitty running fish (login shell stays bash for KDE stability), starship
  prompt, a modern CLI (ripgrep, fd, bat, eza, fzf, zoxide, yazi, delta, fastfetch)
- **Dev:** VS Code, curated language toolchains (Python / Node / Rust / Go /
  Java / C++) with language servers, `direnv` + `nix-direnv` for per-project shells,
  `gh` + GitHub Desktop + `lazygit`, DBeaver, Bruno, Ollama (local LLM), android-tools
- **Containers & VMs:** Docker, Podman, libvirt + virt-manager
- **System engineering:** kubectl/k9s/helm/kubectx, OpenTofu, lazydocker/dive, sops+age,
  Ansible
- **Security tooling:** Wireshark, nmap, tcpdump, Burp Suite, Lynis, ClamAV, auditd
  (kernel audit daemon; no custom rules), KeePassXC; Mullvad + Tailscale + WireGuard
- **Apps:** Chrome, Discord, VLC/mpv, LibreOffice, Thunderbird, EasyEffects
- **Laptop:** power-profiles-daemon, Intel VAAPI hardware video acceleration, fwupd
  (firmware/BIOS updates), zram swap
- **Security & privacy** (`hardening.nix`): kernel/boot hardening, Madaidan-aligned
  sysctls, kernel-module blacklist, locked root account, disabled core dumps,
  Wi-Fi MAC privacy, encrypted DNS (opportunistic DNS-over-TLS with Quad9 fallback),
  Mullvad VPN, AppArmor, firewall — a _desktop-safe_ subset tuned to NOT break KDE,
  Docker, VMs or dev tooling
- **Declarative dotfiles + KDE:** Home Manager manages the shell/terminal dotfiles,
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
| `.github/workflows/`         | CI: flake checks/evaluation, shell regression tests, ShellCheck, Gitleaks history scan                  |

## Quick start (fresh NixOS install)

From a freshly installed NixOS, clone to the source path used by `programs.nh`
and run the bootstrap script:

```sh
mkdir -p ~/Desktop
nix --extra-experimental-features 'nix-command flakes' run nixpkgs#git -- \
  clone https://github.com/26zl/nixos-config ~/Desktop/nixos-config
cd ~/Desktop/nixos-config
sudo bash scripts/bootstrap.sh
```

The bootstrap script generates the hardware profile, creates missing Secure Boot
signing keys from the locked flake, and switches to the new system.

> Regenerating `hardware-configuration.nix` is important: it captures **your**
> disks, filesystems and drivers. The copy committed here belongs to the author's
> machine and will not match yours.

> **Secure Boot is enabled** in this config. Bootstrap creates missing signing
> keys. To opt out, comment out the `./secureboot.nix` import before running it.

## Adapt it to your machine

Before building, change the few values that are specific to a user/host:

| Where               | Change                                                                           |
| ------------------- | -------------------------------------------------------------------------------- |
| `home.nix`          | `home.username` / `home.homeDirectory` → your user                                |
| `configuration.nix` | User, `trusted-users`, hostname, source path, locale, Intel VAAPI and hardware     |
| `flake.nix`         | Home Manager user and the Intel `nixos-hardware` module                           |

The defaults remain specific to this ThinkPad and Intel GPU. Review the hardware
module, graphics driver, disk layout and Secure Boot flow before using another
machine.

## Day-to-day

**Apply local edits** — after changing any file in this repo:

```sh
sudo bash scripts/apply.sh     # copies the repo into /etc/nixos, validates, rebuilds
```

**Update the whole system** — refresh all flake inputs (nixpkgs, home-manager, …)
and rebuild onto the new versions:

```sh
cd ~/Desktop/nixos-config
nix flake update
git diff -- flake.lock
sudo bash scripts/apply.sh
```

Review and commit the lockfile change before a production deployment so the
source commit and deployed generation remain traceable.

**Clean up** — reclaim disk by deleting old generations and deduplicating the store:

```sh
nh clean all --keep 5        # keep the last 5 generations, GC the rest
sudo nix store optimise      # hard-link identical files to save space
```

Old boot entries disappear from the menu after the next rebuild following a cleanup.
`nix-collect-garbage -d` is intentionally omitted because it removes all old
generations and therefore the documented rollback path.

**Roll back** if a rebuild misbehaves — pick an older generation in the boot menu, or:

```sh
sudo nixos-rebuild switch --rollback
```

Generation rollback restores declarative system state only. It does not back up
`/home`, container or VM data, or Secure Boot keys under `/var/lib/sbctl`; keep
those in an encrypted off-device backup and test restoration separately.

## Secure Boot

Secure Boot is **enabled** via [lanzaboote](https://github.com/nix-community/lanzaboote):
`configuration.nix` imports `./secureboot.nix`, which signs the whole boot chain.
A machine without signing keys fails at bootloader install, so a fresh install must
**create keys first** — or opt out by commenting the `./secureboot.nix` import.

One-time setup (ThinkPad instructions; keeps the Windows dual-boot working):

```sh
# 1. Create signing keys (written to /var/lib/sbctl)
sudo nix --extra-experimental-features 'nix-command flakes' \
  shell .#sbctl -c sbctl create-keys
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
declaratively. On another Linux distribution, copy the portable shell and terminal
files:

```sh
cp dotfiles/bashrc ~/.bashrc
cp dotfiles/starship.toml ~/.config/starship.toml
mkdir -p ~/.config/kitty ~/.config/fish ~/.config/fastfetch
cp dotfiles/kitty.conf ~/.config/kitty/kitty.conf
cp dotfiles/config.fish ~/.config/fish/config.fish
cp dotfiles/fastfetch.jsonc ~/.config/fastfetch/config.jsonc
```

Install and configure `nix-direnv` separately outside NixOS; the committed
`direnvrc` uses a NixOS-only path. On Windows, `starship.toml` is
portable, while the shell and Kitty files target Unix.

## Post-install notes

- **Fingerprint:** enroll in System Settings → Users (Synaptics reader).
- **Mullvad:** open the Mullvad VPN app and sign in with your account number.
- **Firefox:** install the
  [Plasma Integration browser add-on](https://addons.mozilla.org/firefox/addon/plasma-integration/);
  the native host is already configured.
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

- `hardware-configuration.nix` contains machine identifiers such as disk UUIDs.
- No credentials, tokens or SSH keys are committed; `.gitignore` and Gitleaks
  enforce that boundary. The public repo still reveals account and machine metadata.
- Claude Code is installed via its own self-updating native installer (runs thanks to
  `programs.nix-ld`), not as a Nix package — so it stays current independently.

## License

Code and configuration are licensed under [MIT](LICENSE).

`wallpaper/nixos.png` incorporates a recolored
[NixOS logo](https://wiki.nixos.org/wiki/Official_NixOS_Wiki:About), licensed
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution:
NixOS project contributors; colors and background were adapted for this config.
