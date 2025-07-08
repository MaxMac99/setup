{
  pkgs,
  lib,
  hostSpec,
  ...
}: let
  ghosttySettings = {
    font-family = "SFMono Nerd Font";
    font-size = 16;
    theme = "tokyonight";
    # background-opacity = 0.9;
    # background-blur = true;
    fullscreen = true;
    cursor-style = "block";
  };
in {
  programs.ghostty = {
    # currently broken on darwin
    enable = !hostSpec.isDarwin;
    settings = ghosttySettings;
  };
  home.file.".config/ghostty/config" = lib.mkIf hostSpec.isDarwin {
    source = (pkgs.formats.toml {}).generate "settings" ghosttySettings;
  };
}
