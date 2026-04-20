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
    "modules/apps/vlc.nix"
    "modules/apps/ghostty.nix"
    "modules/apps/affinity.nix"
    "modules/apps/bambu-studio.nix"
    "modules/apps/autodesk-fusion.nix"
    "modules/apps/arc.nix"
    "modules/apps/docker-desktop.nix"
    "modules/apps/insomnia.nix"
    "modules/apps/k9s.nix"
  ];

  # Ad-hoc packages & Pulumi secrets (personal use only)
  home-manager.users.${config.hostSpec.username} = {config, ...}: {
    sops = {
      defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
      defaultSopsFormat = "yaml";
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      secrets."personal/pulumi-token" = {};
      secrets."personal/pulumi-passphrase" = {};
    };

    programs.zsh.initContent = lib.mkAfter ''
      export PULUMI_ACCESS_TOKEN=$(cat ${config.sops.secrets."personal/pulumi-token".path})
      export PULUMI_CONFIG_PASSPHRASE=$(cat ${config.sops.secrets."personal/pulumi-passphrase".path})
    '';

    home.packages = with pkgs; [
      ffmpeg_6
      rclone
    ];
  };
}
