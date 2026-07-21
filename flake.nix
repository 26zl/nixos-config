{
  description = "NixOS configuration for host 'nixos' (KDE Plasma 6, dual-boot with Windows)";

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
    # Secure Boot (opt-in; activated by importing ./secureboot.nix).
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
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          nixos-hardware.nixosModules.common-cpu-intel
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
              sharedModules = [ plasma-manager.homeModules.plasma-manager ];
              users.lenti = import ./home.nix;
            };
          }
        ];
      };

      # `nix fmt` formats every file (nix/lua/shell/md/yaml/json).
      formatter.${system} = treefmtEval.config.build.wrapper;
      checks.${system}.formatting = treefmtEval.config.build.check self;

      # `nix develop` (or direnv) installs the pre-commit hooks.
      devShells.${system}.default = pkgs.mkShell {
        inherit (preCommit) shellHook;
        buildInputs = preCommit.enabledPackages;
      };
    };
}
