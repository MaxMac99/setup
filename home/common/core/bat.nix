# https://github.com/sharkdp/bat
# https://github.com/eth-p/bat-extras
{pkgs, ...}: let
  # Override individual bat-extras packages to skip tests due to snapshot mismatches
  # These tests fail because bat 0.25.0 changed its output format
  batgrep-no-tests = pkgs.bat-extras.batgrep.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
  batdiff-no-tests = pkgs.bat-extras.batdiff.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
  batman-no-tests = pkgs.bat-extras.batman.overrideAttrs (oldAttrs: {
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
    extraPackages = [
      batgrep-no-tests # search through and highlight files using ripgrep
      batdiff-no-tests # Diff a file against the current git index, or display the diff between to files
      batman-no-tests # read manpages using bat as the formatter
    ];
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
