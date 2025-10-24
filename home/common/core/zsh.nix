{config, lib, hostSpec, ...}: {
  programs.zsh = {
    enable = true;

    enableCompletion = true;
    syntaxHighlighting.enable = true;
    autocd = true;
    autosuggestion.enable = true;
    history = {
      size = 10000;
      share = true;
      ignoreAllDups = true;
    };

    initContent = ''
      # autoSuggestions config

      unsetopt correct # autocorrect commands

      setopt hist_reduce_blanks # remove superfluous blanks from history items
      setopt inc_append_history # save history entries as soon as they are entered

      # auto complete options
      setopt auto_list # automatically list choices on ambiguous completion
      setopt auto_menu # automatically use menu completion
      zstyle ':completion:*' menu select # select completions with arrow keys
      zstyle ':completion:*' group-name "" # group results by category
      zstyle ':completion:::::' completer _expand _complete _ignored _approximate # enable approximate matches for completion

      #      bindkey '^I' forward-word         # tab
      #      bindkey '^[[Z' backward-word      # shift+tab
      #      bindkey '^ ' autosuggest-accept   # ctrl+space

      ${lib.optionalString hostSpec.isWork ''
        export GITHUB_TOKEN=$(cat ${config.sops.secrets."kopf3/github-token".path})
        export PULUMI_ACCESS_TOKEN=$(cat ${config.sops.secrets."kopf3/github-token".path})
      ''}

      # K3s cluster kubeconfig
      export KUBECONFIG=~/.kube/k3s-config
    '';

    oh-my-zsh = {
      enable = true;
      # Standard OMZ plugins pre-installed to $ZSH/plugins/
      # Custom OMZ plugins are added to $ZSH_CUSTOM/plugins/
      # Enabling too many plugins will slowdown shell startup
      plugins = [
        "git"
        "sudo" # press Esc twice to get the previous command prefixed with sudo https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/sudo
        "dirhistory"
        "docker"
        "docker-compose"
        "jsontools"
        "themes"
      ];
      extraConfig = ''
        # Display red dots whilst waiting for completion.
        COMPLETION_WAITING_DOTS="true"
      '';
      theme = "robbyrussell";
    };

    shellAliases = {
      # Overrides those provided by OMZ libs, plugins, and themes.
      # For a full list of active aliases, run `alias`.

      #-------------Bat related------------
      cat = "bat --paging=never";
      diff = "batdiff";
      rg = "batgrep";
      man = "batman";

      #------------Navigation------------
      # doc = "cd $HOME/documents";
      la = "eza -lah";
      ll = "eza -lah";
      ls = "eza";
      lsa = "eza -lah";

      #-----------Nix commands----------------
      nfc = "nix flake check";
      ne = "nix instantiate --eval";
      nb = "nix build";
      ns = "nix shell";

      #-------------Neovim---------------
      e = "nvim";
      vi = "nvim";
      vim = "nvim";

      #-------------SSH---------------
      ssh = "TERM=xterm ssh";

      #-------------Git Goodness-------------
      # just reference `$ alias` and use the defaults, they're good.
    };
  };
}
