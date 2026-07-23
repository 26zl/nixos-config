# NixOS system configuration for host "nixos" (ThinkPad T14 Gen 3, KDE Plasma 6).
#
# Rebuild:   sudo nixos-rebuild switch --flake /etc/nixos#nixos
# Rollback:  sudo nixos-rebuild switch --rollback   (or pick an older generation at boot)

{ config, pkgs, ... }:
let
  # Breeze SDDM login theme with our wallpaper as the background.
  sddmTheme = pkgs.runCommandLocal "sddm-breeze-nixos" { } ''
    theme="$out/share/sddm/themes/breeze-nixos"
    mkdir -p "$theme"
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze/. "$theme"/
    chmod -R u+w "$theme"
    sed -i "s#^background=.*#background=${./wallpaper/nixos.png}#" "$theme/theme.conf"
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ./hardening.nix
    # Secure Boot (lanzaboote) — active. Runbook in secureboot.nix / README.
    ./secureboot.nix
  ];

  # Nix
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = [
      "root"
      "lenti"
    ];
    # Keep dev-shell dependencies alive across garbage collection (nix-direnv).
    keep-outputs = true;
    keep-derivations = true;
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # nh: nicer nixos-rebuild/home-manager with build tree + generation diffs (`nh os switch`).
  programs.nh = {
    enable = true;
    flake = "/home/lenti/Desktop/nixos-config";
  };
  # comma: run any package once without installing it (`, <cmd>`), using a prebuilt index.
  programs.nix-index.enable = true;
  programs.nix-index-database.comma.enable = true;

  # Boot. systemd-boot auto-detects the Windows Boot Manager, so dual-boot needs
  # no extra configuration.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 2; # minimal boot menu; keep 2 for rollback
  boot.loader.systemd-boot.editor = false; # block init=/bin/sh login bypass at the boot menu
  boot.loader.timeout = 5;
  boot.tmp.cleanOnBoot = true;

  # Networking
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  # Time & locale. Windows keeps the hardware clock in local time, so match it.
  time.timeZone = "Europe/Oslo";
  time.hardwareClockInLocalTime = true;
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nb_NO.UTF-8";
    LC_IDENTIFICATION = "nb_NO.UTF-8";
    LC_MEASUREMENT = "nb_NO.UTF-8";
    LC_MONETARY = "nb_NO.UTF-8";
    LC_NAME = "nb_NO.UTF-8";
    LC_NUMERIC = "nb_NO.UTF-8";
    LC_PAPER = "nb_NO.UTF-8";
    LC_TELEPHONE = "nb_NO.UTF-8";
    LC_TIME = "nb_NO.UTF-8";
  };

  # Desktop: KDE Plasma 6 on Wayland
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.displayManager.sddm.theme = "breeze-nixos"; # our wallpaper on the login screen
  services.desktopManager.plasma6.enable = true;
  services.xserver.xkb = {
    layout = "no";
    variant = "";
  };
  console.keyMap = "no";
  programs.dconf.enable = true;
  programs.kdeconnect.enable = true; # opens its own firewall ports
  programs.fish.enable = true; # completions/vendor setup; used as kitty's shell, not login

  # Audio: PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Laptop power & thermals. power-profiles-daemon drives the ThinkPad firmware
  # profiles (DYTC); thermald is deliberately absent — it refuses to run on this
  # platform. Battery charge limit lives in System Settings > Power Management.
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;
  services.irqbalance.enable = true;

  # Intel GPU hardware video acceleration (VAAPI).
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Hardware & maintenance
  services.printing.enable = true;
  services.fstrim.enable = true;
  services.fwupd.enable = true; # firmware/BIOS updates: fwupdmgr refresh && fwupdmgr update
  services.fprintd.enable = true; # Synaptics reader; enroll in System Settings > Users
  hardware.enableRedistributableFirmware = true;
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  zramSwap.enable = true;
  services.earlyoom.enable = true; # kill runaway processes before the system freezes

  # Containers & VMs
  virtualisation.docker.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = false; # docker itself provides the `docker` command
  };
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;

  # Security
  security.sudo.execWheelOnly = true;
  security.apparmor.enable = true;
  security.auditd.enable = true; # kernel audit daemon; no custom detection rules
  services.clamav.updater.enable = true; # keep on-demand scanner definitions current: clamscan / clamdscan

  # Mesh + on-demand VPN alongside Mullvad.
  services.tailscale.enable = true;

  # Local LLM runtime (CPU) serving on localhost:11434; pull models with `ollama run`.
  services.ollama.enable = true;

  # Firefox with telemetry and sponsored content disabled.
  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      EnableTrackingProtection = {
        Value = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      FirefoxHome = {
        Pocket = false;
        SponsoredPocket = false;
        SponsoredTopSites = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        SkipOnboarding = true;
      };
    };
  };

  # Plasma browser integration for Chrome: native-messaging manifest plus a managed
  # policy that auto-installs the "Plasma Integration" extension. Chrome shows
  # "Managed by your organization" because of the policy; drop the policy block to
  # install the extension manually instead.
  environment.etc."opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json".source =
    "${pkgs.kdePackages.plasma-browser-integration}/etc/opt/chrome/native-messaging-hosts/org.kde.plasma.browser_integration.json";
  environment.etc."opt/chrome/policies/managed/plasma-browser-integration.json".text =
    builtins.toJSON
      {
        ExtensionSettings."cimiefiiaegbelhefglklhhakcgmhkai" = {
          installation_mode = "normal_installed";
          update_url = "https://clients2.google.com/service/update2/crx";
        };
      };
  programs.firefox.nativeMessagingHosts.packages = [ pkgs.kdePackages.plasma-browser-integration ];

  # Encrypted DNS (opportunistic DoT). No global DNS= override — a forced resolver
  # would leak around the VPN; Quad9 applies only when a link provides no DNS.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSOverTLS = "opportunistic";
      DNSSEC = "allow-downgrade";
      FallbackDNS = "9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net";
    };
  };

  # Run foreign dynamically linked binaries: VS Code extensions, language servers,
  # and the self-updating Claude Code in ~/.local/bin (kept out of nixpkgs on
  # purpose so its own updater manages it).
  programs.nix-ld.enable = true;

  programs.wireshark.enable = true; # capture permissions via the wireshark group
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
  # Flatpak; add Flathub once:
  #   flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  services.flatpak.enable = true;

  nixpkgs.config.allowUnfree = true;

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    liberation_ttf
    jetbrains-mono
    fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
  ];

  # Users
  users.users.lenti = {
    isNormalUser = true;
    description = "LZ";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker" # note: docker group is root-equivalent
      "libvirtd"
      "wireshark"
    ];
    packages = with pkgs; [ kdePackages.kate ];
  };

  # System packages
  environment.systemPackages = with pkgs; [
    sddmTheme # custom SDDM login theme (Breeze + our wallpaper)

    # Core CLI
    git
    curl
    wget
    file
    tree
    unzip
    zip
    p7zip

    # Editors
    neovim # latest (0.12.x); user config is cloned from the 26zl/nvim repo
    vscode-fhs # FHS build so extensions that ship binaries work

    # Everyday apps
    google-chrome
    discord
    vlc
    mpv
    libreoffice-qt
    thunderbird
    keepassxc
    easyeffects # per-app audio EQ/effects
    kdePackages.okular
    kdePackages.gwenview
    kdePackages.ark
    kdePackages.filelight
    kdePackages.kcalc
    kdePackages.isoimagewriter # write ISOs to USB (Rufus/Etcher analog)

    # Terminal (kitty runs fish; both configured in dotfiles/)
    kitty
    fastfetch # themed system info (run `fastfetch`)

    # Theming — Nord (arctic blue-grey); select in System Settings > Appearance
    nordic # Plasma + Kvantum + GTK Nord theme
    nordzy-icon-theme
    papirus-icon-theme # complete coverage — fixes the missing "?" tray icons
    nordzy-cursor-theme
    kdePackages.qtstyleplugin-kvantum # Kvantum style engine

    # Git tooling
    gh
    github-desktop
    lazygit
    git-lfs
    delta

    # Database / API / local-LLM dev clients
    dbeaver-bin
    bruno
    ollama
    android-tools # adb + fastboot

    # Shell & CLI quality of life
    direnv
    nix-direnv
    starship
    zoxide
    fzf
    yazi
    ripgrep
    fd
    bat
    eza
    jq
    yq
    just
    shellcheck
    shfmt
    httpie
    tmux
    htop
    btop
    wl-clipboard
    docker-compose

    # Nix tooling
    nil
    nixfmt
    statix
    deadnix

    # Languages & package managers (anything else: per-project via direnv)
    python3
    uv
    pipx
    ruff
    nodejs_22
    pnpm
    yarn
    bun
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
    go
    gopls
    gotools
    jdk
    maven
    gradle
    gcc
    clang
    gnumake
    cmake
    pkg-config
    gdb
    pyright
    typescript-language-server
    lua-language-server
    bash-language-server
    yaml-language-server
    dockerfile-language-server
    ansible-language-server
    terraform-ls
    marksman
    stylua
    black
    isort
    prettierd

    # Sysadmin
    ncdu
    dust
    duf
    rsync
    rclone
    dnsutils
    whois
    traceroute
    mtr
    iperf3
    lsof
    strace
    lm_sensors
    pciutils
    usbutils
    lshw
    smartmontools
    ansible
    parted
    gptfdisk

    # Cloud / IaC / Kubernetes (system engineering)
    kubectl
    kubectx
    k9s
    kubernetes-helm
    opentofu
    lazydocker
    dive
    sops
    age

    # Network security (wireshark comes via programs.wireshark)
    nmap
    tcpdump
    socat
    netcat-gnu
    burpsuite # web pentesting proxy
    clamav # on-demand malware scanner
    wireguard-tools

    # Diagnostics
    libva-utils # vainfo: verify VAAPI
    vulkan-tools
  ];

  # Release compatibility marker — never change after install.
  system.stateVersion = "26.05";
}
