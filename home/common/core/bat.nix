# https://github.com/sharkdp/bat
# https://github.com/eth-p/bat-extras
{pkgs, ...}: let
  # Override bat-extras to skip tests due to snapshot mismatches
  bat-extras-no-tests = pkgs.bat-extras.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
in {
  programs.bat = {
    enable = true;
    config = {
      # Git modifications and file header (but no grid)
      style = "changes,header";
      theme = "tokyonight";
      paging = "never";
    };
    extraPackages = builtins.attrValues {
      inherit
        (bat-extras-no-tests)
        batgrep # search through and highlight files using ripgrep
        batdiff # Diff a file against the current git index, or display the diff between to files
        batman # read manpages using bat as the formatter
        ;
    };
    themes = {
      tokyonight = {
        src = pkgs.fetchFromGitHub {
          owner = "folke";
          repo = "tokyonight.nvim";
          rev = "v4.11.0";
          hash = "sha256-pMzk1gRQFA76BCnIEGBRjJ0bQ4YOf3qecaU6Fl/nqLE=";
        };
        file = "extras/sublime/tokyonight_night.tmTheme";
      };
    };
  };

  # Avoid [bat error]: The binary caches for the user-customized syntaxes and themes in
  # '/home/<user>/.cache/bat' are not compatible with this version of bat (0.25.0).
  home.activation.batCacheRebuild = {
    after = ["linkGeneration"];
    before = [];
    data = ''
      ${pkgs.bat}/bin/bat cache --build
    '';
  };
}
