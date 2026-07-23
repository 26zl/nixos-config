# Security & privacy hardening — a desktop-safe subset distilled from a community
# NixOS hardening framework (daily/workstation profile) and ryan4yin's config; see
# README credits. Tuned to not break KDE, Docker, libvirt or dev tooling.
#
# Deliberately excluded as too invasive for this machine: impermanence,
# TPM-backed measured boot, hardened malloc, auditd rule sets, SMT/USB lockdown.

{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Block kexec and runtime kernel-image tampering; there is no disk-backed swap.
  security.protectKernelImage = true;

  # Heap/allocator hardening.
  boot.kernelParams = [
    "slab_nomerge"
    "init_on_alloc=1"
    "page_alloc.shuffle=1"
    "vsyscall=none"
  ];

  # Protocols and buses this laptop never uses; firewire is DMA-capable.
  boot.blacklistedKernelModules = [
    "dccp"
    "sctp"
    "rds"
    "tipc"
    "firewire-core"
    "firewire-ohci"
  ];

  # Never write process memory to disk on crashes.
  systemd.coredump.settings.Coredump = {
    Storage = "none";
    ProcessSizeMax = 0;
  };

  # Root: no direct login (use sudo); su restricted to wheel.
  users.users.root.hashedPassword = "!";
  security.pam.services.su.requireWheel = true;

  boot.kernel.sysctl = {
    # Hide kernel logs and pointers from unprivileged users.
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.sysrq" = 4; # magic SysRq: keyboard-control functions only
    "fs.suid_dumpable" = 0;

    # ptrace/eBPF/perf restricted to root — gdb attach-by-pid, bpftrace and perf
    # need sudo now; relax the matching line if that gets in the way.
    "kernel.yama.ptrace_scope" = 1;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.perf_event_paranoid" = 3;

    # Filesystem link/FIFO protections in world-writable directories.
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;

    # Network: anti-spoofing, no ICMP redirects, SYN-flood and TIME-WAIT
    # protection. rp_filter is loose (2), not strict: Mullvad's policy routing
    # and container traffic fail strict reverse-path checks.
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_rfc1337" = 1;
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # IPv6 privacy (temporary) addresses.
    "net.ipv6.conf.all.use_tempaddr" = 2;
    "net.ipv6.conf.default.use_tempaddr" = 2;

    # Prefer compressed zram swap aggressively over evicting file cache.
    "vm.swappiness" = 150;
  };

  # Wi-Fi privacy: random MAC while scanning, stable per-network when connected.
  networking.networkmanager.wifi.macAddress = "stable";
  networking.networkmanager.wifi.scanRandMacAddress = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Mullvad VPN (daemon + GUI). Sign in with the account number; the app manages
  # its own DNS and kill switch while connected.
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  environment.systemPackages = with pkgs; [
    lynis # audit on demand: sudo lynis audit system
  ];
}
