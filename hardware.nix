# Hardware choices that follow hosts/<name>/host.nix. flake.nix picks the
# matching nixos-hardware modules from the same file (microcode, amdgpu in the
# initrd, Intel VA-API packages, PRIME offload); this covers the rest.
{
  config,
  lib,
  pkgs,
  host,
  ...
}:
let
  laptop = host.formFactor == "laptop";
  has = gpu: lib.elem gpu host.gpus;
  # A laptop whose panel hangs off the integrated GPU while NVIDIA renders on
  # demand (PRIME offload). Everything else displays on the NVIDIA card when
  # there is one.
  hybrid = laptop && has "nvidia" && lib.length host.gpus > 1;
  displayGpu =
    if has "nvidia" && !hybrid then
      "nvidia"
    else if has "intel" then
      "intel"
    else if has "amd" then
      "amd"
    else
      null;
in
{
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;

  # Hardware video decoding. Intel's iHD driver must be named; AMD's radeonsi
  # is found on its own; NVIDIA needs the VA-API bridge and the direct backend.
  environment.sessionVariables = lib.mkMerge [
    (lib.mkIf (displayGpu == "intel") { LIBVA_DRIVER_NAME = "iHD"; })
    (lib.mkIf (displayGpu == "nvidia") {
      LIBVA_DRIVER_NAME = "nvidia";
      NVD_BACKEND = "direct";
    })
  ];
  hardware.graphics.extraPackages = lib.optional (has "nvidia") pkgs.nvidia-vaapi-driver;

  hardware.nvidia = lib.mkIf (has "nvidia") {
    modesetting.enable = true; # Wayland needs it
    open = !host.nvidia.legacy;
    package =
      if host.nvidia.legacy then
        config.boot.kernelPackages.nvidiaPackages.legacy_580
      else
        config.boot.kernelPackages.nvidiaPackages.production;
    powerManagement.enable = true; # keeps VRAM across suspend
    prime = lib.mkIf hybrid {
      nvidiaBusId = host.nvidia.busIds.nvidia;
      intelBusId = lib.mkIf (has "intel") host.nvidia.busIds.igpu;
      amdgpuBusId = lib.mkIf (has "amd") host.nvidia.busIds.igpu;
    };
  };

  # Power. power-profiles-daemon backs KDE's power modes on both form factors
  # and drives laptop firmware profiles; nixos-hardware's laptop module skips
  # TLP while it is on. thermald is left out: it refuses to run on some Intel
  # platforms, and a failed unit at every boot is worse than no daemon.
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;
  services.irqbalance.enable = true;
  services.fwupd.enable = true; # firmware/BIOS updates: fwupdmgr refresh && fwupdmgr update
  services.fstrim.enable = true;
  services.fprintd.enable = host.fingerprint;

  # Windows keeps the hardware clock in local time; match it or the clock
  # jumps by the UTC offset after every switch between the two.
  time.hardwareClockInLocalTime = host.windowsDualBoot;
}
