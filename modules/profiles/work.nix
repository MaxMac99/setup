# Work environment profile - sops setup for the work Mac
{
  config,
  lib,
  ...
}: let
  username = config.hostSpec.username;
  homeDir = config.hostSpec.home;
in {
  home-manager.users.${username} = {
    # Sops secrets for work
    sops = {
      defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
      defaultSopsFormat = "yaml";
      age.keyFile = "${homeDir}/.config/sops/age/keys.txt";
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

    # ⚠️ No GITHUB_TOKEN here any more. It used to be exported into every zsh
    # from the decrypted `kopf3/github-token`, which handed it to every AI
    # agent's shell too. GitHub is a per-session `cloud-login gh` now
    # (modules/profiles/cloud-sessions).
  };
}
