# Core user environment - sets up home-manager with universal user config
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  home-manager.users.${config.hostSpec.username} = {
    imports = [
      inputs.sops-nix.homeManagerModules.sops
      (lib.custom.relativeToRoot "modules/data/host-spec.nix")
      ./git.nix
      ./zsh.nix
      ./tmux.nix
      ./zoxide.nix
      ./bat.nix
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
        ncdu
      ];
    };
  };
}