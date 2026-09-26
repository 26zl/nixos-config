# An all-AMD notebook, the simplest case: everything the defaults in
# lib/host.nix provide is left out.
{
  user = "carol";
  stateVersion = "26.05";

  formFactor = "laptop";
  cpu = "amd";
  gpus = [ "amd" ];

  timeZone = "Asia/Tokyo";
  locale = "ja_JP.UTF-8";
  keyboard = "jp";

  flakePath = "/home/carol/nixos-config";
}
