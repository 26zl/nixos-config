# A hybrid-graphics notebook: Intel iGPU drives the panel, the NVIDIA GPU is
# used through PRIME offload (`nvidia-offload <program>`). Bus IDs are the
# driver's decimal form of the lspci slots, which bootstrap fills in.
{
  user = "bob";
  stateVersion = "26.05";

  formFactor = "laptop";
  cpu = "intel";
  gpus = [
    "intel"
    "nvidia"
  ];
  nvidia.busIds = {
    igpu = "PCI:0:2:0";
    nvidia = "PCI:1:0:0";
  };
  fingerprint = true;

  timeZone = "America/New_York";
  keyboard = "us";

  flakePath = "/home/bob/nixos-config";
}
