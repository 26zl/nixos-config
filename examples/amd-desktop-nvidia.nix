# A gaming desktop: Ryzen with its integrated Radeon plus a GeForce RTX card,
# Windows on another partition. The display runs on the NVIDIA card.
{
  user = "alice";
  userDescription = "Alice";
  stateVersion = "26.05";

  formFactor = "desktop";
  cpu = "amd";
  gpus = [
    "amd"
    "nvidia"
  ];
  windowsDualBoot = true;

  timeZone = "Europe/Berlin";
  locale = "en_US.UTF-8";
  regionalLocale = "de_DE.UTF-8";
  keyboard = "de";

  flakePath = "/home/alice/nixos-config";
}
