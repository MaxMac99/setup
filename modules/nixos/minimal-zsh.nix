{ config, pkgs, lib, ... }:

{
  # Basic zsh configuration for minimal systems without home-manager
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;

    ohMyZsh = {
      enable = true;
      plugins = [ "git" "sudo" "docker" ];
      theme = "robbyrussell";
    };

    shellAliases = {
      # Commonly used aliases
      ls = "ls --color=auto";
      ll = "ls -lah";
      la = "ls -lah";

      # Nix commands
      nfc = "nix flake check";
      nb = "nix build";
      ns = "nix shell";

      # Editor
      e = "vim";
      vi = "vim";

      # SSH
      ssh = "TERM=xterm ssh";
    };

    # System-wide zsh configuration
    interactiveShellInit = ''
      # History settings
      HISTSIZE=10000
      SAVEHIST=10000
      setopt SHARE_HISTORY
      setopt HIST_IGNORE_ALL_DUPS
      setopt HIST_REDUCE_BLANKS
      setopt INC_APPEND_HISTORY

      # Disable autocorrect
      unsetopt correct

      # Auto complete options
      setopt AUTO_LIST
      setopt AUTO_MENU
      zstyle ':completion:*' menu select
      zstyle ':completion:*' group-name ""
      zstyle ':completion:::::' completer _expand _complete _ignored _approximate

      # Don't show the zsh config wizard
      zstyle :compinstall filename '/etc/zshrc'
    '';
  };

  # Set zsh as default shell for users
  users.defaultUserShell = pkgs.zsh;

  # Ensure the user's home has a .zshrc to prevent the config wizard
  system.activationScripts.createUserZshrc = lib.mkIf config.hostSpec.isMinimal ''
    if [ ! -f /home/${config.hostSpec.username}/.zshrc ]; then
      touch /home/${config.hostSpec.username}/.zshrc
      chown ${config.hostSpec.username}:users /home/${config.hostSpec.username}/.zshrc
    fi
  '';
}