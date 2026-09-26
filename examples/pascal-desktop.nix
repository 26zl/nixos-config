# An older desktop with a GTX 10-series card: the current driver dropped
# Pascal, so the 580 legacy branch with the proprietary kernel modules is used.
{
  user = "dave";
  stateVersion = "26.05";

  formFactor = "desktop";
  cpu = "intel";
  gpus = [ "nvidia" ];
  nvidia.legacy = true;

  timeZone = "Europe/London";
  keyboard = "gb";

  flakePath = "/home/dave/nixos-config";
}
