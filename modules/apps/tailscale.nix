# Tailscale - nixos service on linux, homebrew cask on darwin
{
  pkgs,
  lib,
  ...
}: {
  services.tailscale = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    openFirewall = true;
  };
  homebrew.casks = lib.mkIf pkgs.stdenv.isDarwin ["tailscale-app"];
}
