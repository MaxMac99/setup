{config, pkgs, ...}: {
  home-manager.users.${config.hostSpec.username}.home.packages = [pkgs.zoom-us];
}