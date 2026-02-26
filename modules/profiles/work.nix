# Work environment profile - sops secrets, git config, shell env vars
{
  config,
  lib,
  ...
}: let
  username = config.hostSpec.username;
  homeDir = config.hostSpec.home;
in {
  home-manager.users.${username} = {config, ...}: {
    # Sops secrets for work
    sops = {
      defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
      defaultSopsFormat = "yaml";
      age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
      secrets."kopf3/github-token" = {};
      secrets."kopf3/pulumi-token" = {};
    };

    # Fix for sops-nix on macOS - ensure launchd agent has correct PATH
    launchd.agents.sops-nix = {
      enable = true;
      config = {
        EnvironmentVariables = {
          PATH = lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin";
        };
      };
    };

    # Git: work directory override
    programs.git.includes = [
      {
        condition = "gitdir:~/kopf3/";
        path = "~/.gitconfig-kopf3";
      }
    ];
    home.file.".gitconfig-kopf3".text = ''
      [user]
        email = max.vissing@kopf3.de
    '';

    # Zsh: export work env vars
    programs.zsh.initContent = lib.mkAfter ''
      export GITHUB_TOKEN=$(cat ${config.sops.secrets."kopf3/github-token".path})
      export PULUMI_ACCESS_TOKEN=$(cat ${config.sops.secrets."kopf3/github-token".path})
    '';
  };
}