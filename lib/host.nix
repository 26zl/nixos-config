# Fills in the defaults for a host file (hosts/<name>/host.nix or an example)
# and rejects values the rest of the configuration cannot handle, naming the
# file in the error.
{ lib }:
file: raw:
let
  defaults = {
    userDescription = "";
    formFactor = "desktop";
    gpus = [ ];
    nvidia = {
      # Turing (RTX 20 / GTX 16) and newer run NVIDIA's open kernel modules.
      # Maxwell, Pascal and Volta need the 580 legacy driver instead.
      legacy = false;
      # PCI bus IDs for PRIME offload on a laptop with an integrated GPU next
      # to the NVIDIA one, in the driver's decimal form ("PCI:1:0:0").
      busIds = { };
    };
    fingerprint = false;
    windowsDualBoot = false;
    timeZone = "Etc/UTC";
    locale = "en_US.UTF-8";
    regionalLocale = null;
    keyboard = "us";
  };
  required = [
    "user"
    "stateVersion"
    "cpu"
    "flakePath"
  ];
  gpuNames = [
    "amd"
    "intel"
    "nvidia"
  ];

  host = lib.recursiveUpdate defaults raw;
  missing = lib.filter (key: !(raw ? ${key})) required;
  unknown = lib.subtractLists (required ++ lib.attrNames defaults) (lib.attrNames raw);
  badGpus = lib.subtractLists gpuNames host.gpus;
  hybrid = host.formFactor == "laptop" && lib.elem "nvidia" host.gpus && lib.length host.gpus > 1;
  list = lib.concatStringsSep ", ";

  checks = [
    {
      ok = missing == [ ];
      message = "missing ${list missing}";
    }
    {
      ok = unknown == [ ];
      message = "unknown settings ${list unknown}";
    }
    {
      ok = host.formFactor == "desktop" || host.formFactor == "laptop";
      message = "formFactor must be desktop or laptop";
    }
    {
      ok = host.cpu == "amd" || host.cpu == "intel";
      message = "cpu must be amd or intel";
    }
    {
      ok = badGpus == [ ];
      message = "gpus may only contain ${list gpuNames}";
    }
    {
      ok = !hybrid || (host.nvidia.busIds ? igpu && host.nvidia.busIds ? nvidia);
      message = "a laptop with an NVIDIA GPU next to an integrated one needs nvidia.busIds.igpu and nvidia.busIds.nvidia for PRIME offload";
    }
  ];
in
lib.foldr (check: value: lib.throwIfNot check.ok "${file}: ${check.message}" value) host checks
