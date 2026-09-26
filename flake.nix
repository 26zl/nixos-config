{
  description = "NixOS configuration: KDE Plasma 6, hardened, one host file per machine";

  inputs = {
    # Unstable channel. For stable, point at e.g. github:nixos/nixpkgs/nixos-26.05
    # and rebuild with --recreate-lock-file.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secure Boot is enabled by the secureboot.nix import in configuration.nix.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      plasma-manager,
      nixos-hardware,
      nix-index-database,
      treefmt-nix,
      git-hooks,
      lanzaboote,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;
      loadHost = import ./lib/host.nix { inherit lib; };

      # nixos-hardware's common modules for what a host file declares.
      hardwareModules =
        host:
        with nixos-hardware.nixosModules;
        let
          has = gpu: lib.elem gpu host.gpus;
          laptop = host.formFactor == "laptop";
        in
        [
          common-pc
          common-pc-ssd
        ]
        ++ lib.optional laptop common-pc-laptop
        ++ lib.optionals (host.cpu == "amd") [
          common-cpu-amd
          common-cpu-amd-pstate
        ]
        ++ lib.optional (host.cpu == "intel") common-cpu-intel-cpu-only
        ++ lib.optional (has "amd") common-gpu-amd
        ++ lib.optional (has "intel") common-gpu-intel
        # PRIME offload only where an integrated GPU drives a laptop's panel;
        # everywhere else the NVIDIA card is the display.
        ++ lib.optional (has "nvidia") (
          if laptop && lib.length host.gpus > 1 then common-gpu-nvidia else common-gpu-nvidia-nonprime
        );

      mkSystem =
        {
          name,
          host,
          hardwareConfiguration,
        }:
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs host; };
          modules = [
            ./configuration.nix
            hardwareConfiguration
            { networking.hostName = name; }
            nix-index-database.nixosModules.nix-index
            # Provides the boot.lanzaboote options; inert until ./secureboot.nix
            # sets enable = true (default is off, so this changes nothing on its own).
            lanzaboote.nixosModules.lanzaboote
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-bak";
                extraSpecialArgs = { inherit host; };
                sharedModules = [ plasma-manager.homeModules.plasma-manager ];
                users.${host.user} = import ./home.nix;
              };
            }
          ]
          ++ hardwareModules host;
        };

      # One system per hosts/<name>/ directory; the name is the hostname. The
      # directories are git-ignored, so a clone has none until bootstrap runs.
      hostNames = lib.attrNames (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./hosts + "/${name}/host.nix")
        ) (builtins.readDir ./hosts)
      );
      hosts = lib.genAttrs hostNames (
        name:
        mkSystem {
          inherit name;
          host = loadHost "hosts/${name}/host.nix" (import ./hosts/${name}/host.nix);
          hardwareConfiguration = ./hosts/${name}/hardware-configuration.nix;
        }
      );

      # examples/<name>.nix are host files for several kinds of machines. They
      # stand in for real hosts in CI, which builds each of them.
      exampleNames = map (lib.removeSuffix ".nix") (
        lib.filter (file: file != "hardware-configuration.nix" && lib.hasSuffix ".nix" file) (
          lib.attrNames (builtins.readDir ./examples)
        )
      );
      examples = lib.genAttrs exampleNames (
        name:
        mkSystem {
          inherit name;
          host = loadHost "examples/${name}.nix" (import ./examples/${name}.nix);
          hardwareConfiguration = ./examples/hardware-configuration.nix;
        }
      );

      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
      preCommit = git-hooks.lib.${system}.run {
        src = ./.;
        hooks = {
          nixfmt-rfc-style = {
            enable = true;
            package = pkgs.nixfmt;
          };
          statix.enable = true;
          shellcheck.enable = true;
        };
      };
    in
    {
      nixosConfigurations = hosts;

      # `nix fmt` formats every file (nix/lua/shell/md/yaml/json).
      formatter.${system} = treefmtEval.config.build.wrapper;
      packages.${system}.sbctl = pkgs.sbctl;
      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
        pre-commit = preCommit;
        # Evaluating each example host down to its derivation path runs every
        # assertion in a minute, without building anything: the quick check.
        example-hosts = pkgs.writeText "example-hosts" (
          lib.concatMapStringsSep "\n" (
            name:
            "${name} ${
              builtins.unsafeDiscardStringContext examples.${name}.config.system.build.toplevel.drvPath
            }"
          ) exampleNames
        );
      }
      # Evaluation accepts a configuration whose packages cannot be built --
      # a broken derivation in nixpkgs only surfaces when something actually
      # realises the closure. CI builds every example system, so a rebuild on
      # a real machine is never the first thing to find out.
      // lib.mapAttrs' (
        name: cfg: lib.nameValuePair "example-${name}" cfg.config.system.build.toplevel
      ) examples
      // lib.mapAttrs' (
        name: cfg: lib.nameValuePair "toplevel-${name}" cfg.config.system.build.toplevel
      ) hosts;

      # `nix develop` (or direnv) installs the pre-commit hooks.
      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommit) shellHook;
        buildInputs = preCommit.enabledPackages;
      };
    };
}
