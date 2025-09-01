{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = lib.flatten [
    inputs.sops-nix.homeManagerModules.sops
    ./fonts.nix
    ./git.nix
    ./tmux.nix
    ./zoxide.nix
    ./bat.nix
    ./zsh.nix
    ./ssh.nix
    ./nvf
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
    packages = with pkgs; [
      sops
      age
      ssh-to-age
      gh
      nodejs_24
      pwgen
      claude-code
      exiftool
      curl
      jq
      nix-tree
      zip
      unzip
      tree
      fzf
      eza
      cargo
      rustc
      nixpkgs-fmt
      selene
      statix
      dotenv-cli
      pulumi
      google-cloud-sdk
      pulumiPackages.pulumi-nodejs
      htop
      maven
      temurin-bin-21
      yarn
      filezilla
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
