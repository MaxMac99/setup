# VLC - nixpkgs on linux, homebrew cask on darwin
{pkgs, lib, ...}: {
  environment.systemPackages = lib.mkIf pkgs.stdenv.isLinux [pkgs.vlc];
  homebrew.casks = lib.mkIf pkgs.stdenv.isDarwin ["vlc"];
}