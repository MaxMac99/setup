{
  config,
  lib,
  pkgs,
  inputs,
  hostSpec,
  ...
}: {
  imports =
    lib.flatten [
      (lib.custom.relativeToRoot "modules/common/host-spec.nix")
      inputs.sops-nix.homeManagerModules.sops
      ./git.nix
      ./tmux.nix
      ./zoxide.nix
      ./bat.nix
      ./zsh.nix
      ./ssh.nix
      ./nvf
    ]
    ++ lib.optionals (!hostSpec.isServer) [
      ./fonts.nix
    ]
    ++ lib.optionals (!hostSpec.isMinimal) [
      ./gcloud.nix
    ];

  programs.home-manager.enable = true;

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    stateVersion = lib.mkDefault "23.05";
    sessionVariables = {
      EDITOR = "nvim";
      XDG_CONFIG_HOME = "$HOME/.config";
    };
    packages = with pkgs;
      [
        sops
        age
        ssh-to-age
        gh
        pwgen
        curl
        jq
        nix-tree
        zip
        unzip
        tree
        fzf
        eza
        htop
      ]
      ++ lib.optionals (!config.hostSpec.isMinimal) [
        claude-code
        exiftool
        cargo
        nixpkgs-fmt
        selene
        statix
        dotenv-cli
        pulumi
        pulumiPackages.pulumi-nodejs
        openapi-generator-cli
      ]
      ++ lib.optionals (!config.hostSpec.isServer && !config.hostSpec.isMinimal) [
        azure-cli
        nodejs_24
        maven
        temurin-bin-21
        yarn
        zoom-us
      ];
  };

  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
    defaultSopsFormat = "yaml";
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    secrets."kopf3/github-token" = {};
    secrets."kopf3/pulumi-token" = {};
  };
}
