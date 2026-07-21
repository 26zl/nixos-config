{
  projectRootFile = "flake.nix";
  settings.global.excludes = [
    "flake.lock"
    "LICENSE"
    "*.jsonc" # fastfetch config keeps // comments prettier would strip
  ];
  programs = {
    nixfmt.enable = true; # .nix
    stylua.enable = true; # .lua
    shfmt.enable = true; # shell scripts
    prettier.enable = true; # .md .json .yaml
  };
}
