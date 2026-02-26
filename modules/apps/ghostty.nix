# Ghostty terminal - cask on darwin (HM broken), HM program on linux
{
  config,
  pkgs,
  lib,
  ...
}: let
  ghosttySettings = {
    font-family = "SFMono Nerd Font";
    font-size = 16;
    theme = "Dark Pastel";
    fullscreen = true;
    cursor-style = "block";
    scrollback-limit = 200000000;
  };
in {
  # Darwin: use homebrew cask (HM program currently broken on darwin)
  homebrew.casks = lib.mkIf pkgs.stdenv.isDarwin ["ghostty"];

  home-manager.users.${config.hostSpec.username} = {
    # Linux: use home-manager program
    programs.ghostty = lib.mkIf pkgs.stdenv.isLinux {
      enable = true;
      settings = ghosttySettings;
    };
    # Darwin: write config file manually
    home.file.".config/ghostty/config" = lib.mkIf pkgs.stdenv.isDarwin {
      source = (pkgs.formats.toml {}).generate "settings" ghosttySettings;
    };
  };
}