# Secure Boot via lanzaboote (github:nix-community/lanzaboote).
#
# OPT-IN: this file only takes effect once it is imported from
# configuration.nix. Do NOT enable it before signing keys exist, or the build
# will have nothing to sign the boot chain with. One-time runbook:
#
#   1. sudo nix-shell -p sbctl --run 'sbctl create-keys'   # writes /var/lib/sbctl
#   2. uncomment the ./secureboot.nix import + rebuild      # signs the boot chain
#      sudo sbctl verify                                    # boot files show signed
#   3. reboot -> "Reboot into Firmware" -> Security -> Secure Boot:
#        set Secure Boot = enabled, then "Reset to Setup Mode", F10 to save
#      (do NOT pick "Clear All Secure Boot Keys" — that wipes the dbx)
#   4. back in NixOS:  sudo sbctl enroll-keys --microsoft   # keeps Windows bootable
#   5. reboot; confirm:  bootctl status  ->  Secure Boot: enabled (user)
{ lib, pkgs, ... }:
{
  environment.systemPackages = [ pkgs.sbctl ]; # inspect/verify Secure Boot

  # lanzaboote replaces the stock systemd-boot module; force it off.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };
}
