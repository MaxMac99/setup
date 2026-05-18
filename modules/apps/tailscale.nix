# Tailscale - nixos service on linux, homebrew cask on darwin
# NixOS hosts that need peer-to-peer connectivity should also set
# services.tailscale.openFirewall = true; in their host config.
{
  pkgs,
  lib,
  ...
}: {
  services.tailscale.enable = lib.mkIf pkgs.stdenv.isLinux true;
  homebrew.casks = lib.mkIf pkgs.stdenv.isDarwin ["tailscale-app"];
}
