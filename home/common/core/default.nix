{
  config,
  lib,
  pkgs,
  hostSpec,
  ...
}: let
  platform =
    if hostSpec.isDarwin
    then "darwin"
    else "nixos";
in {
  imports = lib.flatten [
    ./fonts.nix
    ./git.nix
    ./tmux.nix
    ./zoxide.nix
    ./bat.nix
    ./zsh.nix
    # ./nixvim
    ./nvf
  ];

  programs.home-manager.enable = true;

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    stateVersion = lib.mkDefault "23.05";
    packages = with pkgs; [
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
      zoom-us
    ];
  };
}
