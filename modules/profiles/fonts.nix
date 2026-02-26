# Fonts profile - SFMono Nerd Font
{config, pkgs, ...}: {
  home-manager.users.${config.hostSpec.username} = {
    fonts.fontconfig.enable = true;
    home.packages = [
      (pkgs.callPackage pkgs.stdenvNoCC.mkDerivation {
        name = "sfmono-nerd-font";
        dontConfigue = true;
        src = pkgs.fetchzip {
          url = "https://github.com/epk/SF-Mono-Nerd-Font/archive/refs/tags/v18.0d1e1.0.zip";
          sha256 = "sha256-7Z1i4/XdDhXc3xPqRpnzZoCB75HzyVqRDh4qh4jJdKI=";
          stripRoot = false;
        };
        installPhase = ''
          mkdir -p $out/share/fonts
          cp -R $src $out/share/fonts/opentype/
        '';
        meta = {description = "A SFMono Pack font";};
      })
    ];
  };
}