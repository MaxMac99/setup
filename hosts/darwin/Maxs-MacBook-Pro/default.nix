{
  config,
  lib,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  hostSpec = {
    username = "maxvissing";
    hostName = "Maxs-MacBook-Pro";
  };

  imports = map lib.custom.relativeToRoot [
    # User profiles
    "modules/profiles/core-user"
    "modules/profiles/development.nix"
    "modules/profiles/fonts.nix"
    "modules/profiles/gcloud.nix"
    "modules/profiles/full-nvim.nix"
    "modules/profiles/darwin-nvim.nix"
    "modules/profiles/personal-ssh.nix"
    # Applications
    "modules/apps/google-chrome.nix"
    "modules/apps/discord.nix"
    "modules/apps/intellij"
    "modules/apps/rust-rover.nix"
    "modules/apps/zed.nix"
    "modules/apps/vlc.nix"
    "modules/apps/ghostty.nix"
    "modules/apps/affinity.nix"
    "modules/apps/bambu-studio.nix"
    "modules/apps/autodesk-fusion.nix"
    "modules/apps/arc.nix"
    "modules/apps/docker-desktop.nix"
  ];

  # Ad-hoc packages
  home-manager.users.${config.hostSpec.username}.home.packages = with pkgs; [
    ffmpeg_6
    rclone
  ];
}