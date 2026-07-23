{ ... }:
let
  wp = ./wallpaper/nixos.png;
in
{
  home.username = "lenti";
  home.homeDirectory = "/home/lenti";
  home.stateVersion = "26.05";

  # Dotfiles from this repo, managed declaratively (edit in dotfiles/, rebuild).
  home.file = {
    ".bashrc".source = ./dotfiles/bashrc;
    ".config/starship.toml".source = ./dotfiles/starship.toml;
    ".config/direnv/direnvrc".source = ./dotfiles/direnvrc;
    ".config/kitty/kitty.conf".source = ./dotfiles/kitty.conf;
    ".config/fish/config.fish".source = ./dotfiles/config.fish;
    ".config/fastfetch/config.jsonc".source = ./dotfiles/fastfetch.jsonc;
  };

  # KDE Plasma: dark Nord + NixOS "snowflake" blue accent + NixOS wallpaper,
  # applied declaratively. colorScheme (reliable) instead of lookAndFeel.
  programs.plasma = {
    enable = true;
    workspace = {
      colorScheme = "NordicDarker";
      iconTheme = "Papirus-Dark";
      wallpaper = wp;
      cursor = {
        theme = "Nordzy-cursors";
        size = 24;
      };
    };
    configFile = {
      kdeglobals.General = {
        AccentColor = "126,186,228";
        accentColorFromWallpaper = false;
      };
      # Snappier UI: shorter animations + disable the Baloo file indexer
      # (a big background CPU/disk saver; re-enable if you want file-content search).
      kdeglobals.KDE.AnimationDurationFactor = 0.5;
      baloofilerc."Basic Settings"."Indexing-Enabled" = false;
      # Disable KDE annoyances: zoom/magnifier + shake-to-find cursor (both easy
      # to trigger by accident), the Meta-alone launcher popup, the app-launch
      # bounce cursor, and the boot splash screen.
      kwinrc.Plugins.zoomEnabled = false;
      kwinrc.Plugins.shakecursorEnabled = false;
      kwinrc.ModifierOnlyShortcuts.Meta = "";
      klaunchrc.BusyCursorSettings.Bouncing = false;
      ksplashrc.KSplash.Engine = "none";
      ksplashrc.KSplash.Theme = "None";
      # Lock screen (also shown when resuming from sleep).
      kscreenlockerrc = {
        Greeter.WallpaperPlugin = "org.kde.image";
        "Greeter/Wallpaper/org.kde.image/General".Image = "${wp}";
      };
    };
  };
}
