#!/usr/bin/env bash
# Bootstrap this configuration on a fresh NixOS install, or rebuild an existing
# host after regenerating its hardware profile. Run from the repository root,
# with sudo from your normal account (that account becomes the host's user):
#
#   sudo bash scripts/bootstrap.sh <host>
#
# <host> becomes the hostname and the flake output. A new host gets a
# hosts/<host>/ directory holding host.nix, filled in from what this script
# detects (account, CPU, GPUs, form factor, Windows, locale), and the
# generated hardware-configuration.nix. hosts/ is git-ignored: the directory
# stays on this machine, and the build reads it through a path: flake
# reference, which does not need it tracked. Review host.nix before the first
# build when the detection prints anything doubtful.
set -euo pipefail

die() {
  echo "$*" >&2
  exit 1
}

if [[ $EUID -ne 0 ]]; then
  die "This script needs root. Re-run: sudo bash scripts/bootstrap.sh <host>"
fi

HOST="${1:-}"
[[ -n $HOST ]] || die "Usage: sudo bash scripts/bootstrap.sh <host>   (the name becomes the hostname)"
[[ $HOST =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Host names use lowercase letters, digits and dashes."

user="${SUDO_USER:-}"
[[ -n $user && $user != root ]] ||
  die "Run with sudo from your normal account, not as root: that account becomes the host's user."

script_path="$(realpath "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$script_path")/.." && pwd)"
cd "$REPO"

if [[ ! -f flake.nix ]]; then
  die "flake.nix not found in $REPO — run this from the cloned repository."
fi

host_dir="$REPO/hosts/$HOST"
FLAKES=(--option extra-experimental-features 'nix-command flakes')

# --- detection ---------------------------------------------------------------

# "<vendor> <device> <slot>" per display controller, lowercase hex.
pci_gpus() {
  local dev class vendor device
  for dev in /sys/bus/pci/devices/*; do
    read -r class 2>/dev/null <"$dev/class" || continue
    [[ $class == 0x03* ]] || continue
    read -r vendor <"$dev/vendor"
    read -r device <"$dev/device"
    echo "${vendor#0x} ${device#0x} ${dev##*/}"
  done
}

# "PCI:1:0:0" from the slot "0000:01:00.0": the NVIDIA driver wants decimal.
bus_id() {
  local slot="${1#*:}" bus dev fn
  bus="${slot%%:*}"
  dev="${slot#*:}"
  dev="${dev%%.*}"
  fn="${slot##*.}"
  printf 'PCI:%d:%d:%d' "0x$bus" "0x$dev" "0x$fn"
}

# SMBIOS chassis types 8-11, 14 and 30-32 are portable; otherwise a system
# battery decides (mice and controllers report theirs with scope "Device").
is_laptop() {
  local chassis="" supply type scope
  read -r chassis 2>/dev/null </sys/class/dmi/id/chassis_type || true
  case "$chassis" in
  8 | 9 | 10 | 11 | 14 | 30 | 31 | 32) return 0 ;;
  3 | 4 | 5 | 6 | 7 | 13 | 15 | 16 | 17 | 23 | 24 | 35 | 36) return 1 ;;
  esac
  for supply in /sys/class/power_supply/*; do
    read -r type 2>/dev/null <"$supply/type" || continue
    [[ $type == Battery ]] || continue
    scope=""
    read -r scope 2>/dev/null <"$supply/scope" || true
    [[ $scope == Device ]] || return 0
  done
  return 1
}

# The value of `name = "value";` in the given Nix files: the installer's
# configuration.nix on a fresh system, or the host file of an earlier
# deployment of this repository under /etc/nixos.
nix_setting() { # name file...
  local name="$1"
  shift
  sed -n "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$@" 2>/dev/null | head -n 1
}

detect_host() {
  local vendor device slot cpu form_factor="desktop" fingerprint=false windows=false
  local installer=/etc/nixos/configuration.nix
  local deployed=(/etc/nixos/hosts/*/host.nix)
  local gpus=() nvidia_device=-1 nvidia_slot="" igpu_slot="" nvidia_legacy=false
  local time_zone locale regional keyboard state_version description

  case "$(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo)" in
  AuthenticAMD) cpu=amd ;;
  GenuineIntel) cpu=intel ;;
  *) die "Unsupported CPU vendor: $(awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo)" ;;
  esac

  while read -r vendor device slot; do
    case "$vendor" in
    1002)
      gpus+=(amd)
      igpu_slot="$slot"
      ;;
    8086)
      gpus+=(intel)
      igpu_slot="$slot"
      ;;
    10de)
      # newest NVIDIA GPU decides: Turing (0x1e00) and newer run the current
      # driver, Maxwell to Volta (0x1340-0x1dff) the 580 legacy branch, older
      # cards stay on nouveau
      if ((16#$device > nvidia_device)); then
        nvidia_device=$((16#$device))
        nvidia_slot="$slot"
      fi
      ;;
    esac
  done < <(pci_gpus)
  if ((nvidia_device >= 0x1e00)); then
    gpus+=(nvidia)
  elif ((nvidia_device >= 0x1340)); then
    gpus+=(nvidia)
    nvidia_legacy=true
  elif ((nvidia_device >= 0)); then
    echo "    NVIDIA GPU older than Maxwell: no packaged driver supports it, leaving it on nouveau" >&2
  fi

  is_laptop && form_factor=laptop
  # a reader that announces itself, or fprintd already running on this system
  if grep -qil fingerprint /sys/bus/usb/devices/*/product 2>/dev/null ||
    [[ -e /etc/systemd/system/fprintd.service ]]; then
    fingerprint=true
  fi
  # Windows on the same ESP (systemd-boot lists it); a second disk needs a manual edit
  find /boot/EFI -maxdepth 3 -iname bootmgfw.efi 2>/dev/null | grep -q . && windows=true

  time_zone=$(nix_setting time.timeZone "$installer")
  [[ -n $time_zone ]] || time_zone=$(nix_setting timeZone "${deployed[@]}")
  [[ -n $time_zone ]] || time_zone=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  : "${time_zone:=Etc/UTC}"
  locale=$(nix_setting i18n.defaultLocale "$installer")
  [[ -n $locale ]] || locale=$(nix_setting locale "${deployed[@]}")
  [[ -n $locale ]] || locale=$(localectl status 2>/dev/null | sed -n 's/.*LANG=//p' | head -n 1)
  : "${locale:=en_US.UTF-8}"
  regional=$(nix_setting LC_TIME "$installer")
  [[ -n $regional ]] || regional=$(nix_setting regionalLocale "${deployed[@]}")
  [[ $regional != "$locale" ]] || regional=""
  keyboard=$(nix_setting layout "$installer")
  [[ -n $keyboard ]] || keyboard=$(nix_setting keyboard "${deployed[@]}")
  [[ -n $keyboard ]] || keyboard=$(nix_setting console.keyMap "$installer")
  [[ -n $keyboard ]] || keyboard=$(localectl status 2>/dev/null | sed -n 's/.*X11 Layout: //p' | head -n 1)
  : "${keyboard:=us}"
  state_version=$(nix_setting system.stateVersion "$installer")
  [[ -n $state_version ]] || state_version=$(nix_setting stateVersion "${deployed[@]}")
  if [[ -z $state_version ]]; then
    # only the release this machine was installed from is right, and nothing
    # on the system records it once the installer's configuration.nix is gone
    state_version=$(nixos-version | cut -d. -f1,2)
    echo "    stateVersion: no installed-from release found; $state_version is the running one" >&2
    if [[ -t 0 ]]; then
      read -rp "    Release this machine was installed from [$state_version]: " answer
      [[ -z $answer ]] || state_version="$answer"
    fi
  fi
  description=$(getent passwd "$user" | cut -d: -f5 | cut -d, -f1)

  echo "==> Detected: $form_factor, $cpu CPU, GPUs: ${gpus[*]:-none}$($nvidia_legacy && echo ' (NVIDIA legacy 580 driver)')"
  echo "    user $user, fingerprint reader: $fingerprint, Windows: $windows"
  echo "    time zone $time_zone, locale $locale${regional:+ (formats $regional)}, keyboard $keyboard, stateVersion $state_version"

  mkdir -p "$host_dir"
  {
    cat <<EOF
# Written by scripts/bootstrap.sh from what it detected on $(date '+%Y-%m-%d');
# lib/host.nix lists the defaults and checks the values. The directory name is
# the hostname and the flake output (nixosConfigurations.$HOST).
{
  user = "$user";
  userDescription = "$description";

  # The release this machine was installed from. Never raise it: it pins how
  # existing service state is migrated, not which packages are installed.
  stateVersion = "$state_version";

  formFactor = "$form_factor"; # laptop | desktop
  cpu = "$cpu"; # intel | amd
  gpus = [ $(printf '"%s" ' "${gpus[@]}")]; # any of intel, amd, nvidia
EOF
    if [[ " ${gpus[*]} " == *" nvidia "* ]]; then
      echo "  nvidia = {"
      echo "    # Turing (RTX 20 / GTX 16) and newer run the open kernel modules;"
      echo "    # Maxwell, Pascal and Volta need the 580 legacy driver instead."
      echo "    legacy = $nvidia_legacy;"
      if [[ $form_factor == laptop && -n $igpu_slot ]]; then
        echo "    # PRIME offload: the integrated GPU drives the panel, NVIDIA renders on demand"
        echo "    busIds = {"
        echo "      igpu = \"$(bus_id "$igpu_slot")\";"
        echo "      nvidia = \"$(bus_id "$nvidia_slot")\";"
        echo "    };"
      fi
      echo "  };"
    fi
    cat <<EOF
  fingerprint = $fingerprint; # fprintd; enroll in System Settings > Users
  windowsDualBoot = $windows; # Windows keeps the RTC in local time; systemd-boot lists it

  # Locale. regionalLocale sets the LC_* formats (dates, paper, money) while
  # \`locale\` stays the UI language; null keeps everything in \`locale\`.
  timeZone = "$time_zone";
  locale = "$locale";
  regionalLocale = ${regional:+\"$regional\"}${regional:-null};
  keyboard = "$keyboard"; # console keymap and X11 layout

  # This clone, for \`nh os switch\`.
  flakePath = "$REPO";
}
EOF
  } >"$host_dir/host.nix"
  echo "==> Wrote hosts/$HOST/host.nix — review it before the first build if anything above looks off"
}

# --- host directory -----------------------------------------------------------

if [[ -f $host_dir/host.nix ]]; then
  existing_user=$(sed -n 's/^[[:space:]]*user = "\([^"]*\)";.*/\1/p' "$host_dir/host.nix" | head -n 1)
  if [[ -n $existing_user ]] && ! id -u "$existing_user" >/dev/null 2>&1; then
    die "hosts/$HOST/host.nix belongs to the user '$existing_user', who does not exist on this machine.
Pick another host name, or edit that file if this machine is really '$HOST'."
  fi
  echo "==> Reusing hosts/$HOST/host.nix"
else
  detect_host
fi

echo "==> Generating hosts/$HOST/hardware-configuration.nix for this machine"
hardware_tmp="$(mktemp "$host_dir/hardware-configuration.nix.XXXXXX")"
cleanup_hardware_tmp() {
  rm -f -- "$hardware_tmp"
}
trap cleanup_hardware_tmp EXIT
nixos-generate-config --show-hardware-config >"$hardware_tmp"
if [[ ! -s $hardware_tmp ]]; then
  echo "Generated hardware configuration is empty; keeping the existing file." >&2
  exit 1
fi
chmod 0644 "$hardware_tmp"
mv -- "$hardware_tmp" "$host_dir/hardware-configuration.nix"
trap - EXIT
chown -R --reference="$REPO" "$host_dir"

# Secure Boot (secureboot.nix) signs the boot chain, so signing keys must exist
# before the first build. Harmless if you later comment out the import to opt out.
if [[ ! -d /var/lib/sbctl/keys ]]; then
  echo "==> Creating Secure Boot signing keys (/var/lib/sbctl)"
  nix "${FLAKES[@]}" shell "${REPO}#sbctl" -c sbctl create-keys
fi

# path: reads the working tree as it is, so the git-ignored host directory is
# seen without being tracked.
echo "==> Building and switching to the new system"
nixos-rebuild switch --flake "path:${REPO}#${HOST}" "${FLAKES[@]}"

echo "==> Done. Reboot to land on the new generation cleanly."
echo "    Secure Boot: finish enrollment in the firmware — see README 'Secure Boot'."
