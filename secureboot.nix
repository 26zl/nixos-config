# Secure Boot via lanzaboote (github:nix-community/lanzaboote).
# This module is active by default; signing keys must exist before the first
# rebuild. See the README for enrollment, verification and opt-out steps.
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
