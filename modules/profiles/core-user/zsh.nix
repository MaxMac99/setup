{config, ...}: {
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

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

      # robbyrussell shows only the leaf directory (%c), which is useless with the
      # worktree layout where every leaf is just the branch name. Show up to the
      # last 3 components instead, eliding the rest.
      PROMPT="%(?:%{$fg_bold[green]%}%1{➜%} :%{$fg_bold[red]%}%1{➜%} ) %{$fg[cyan]%}%(4~|…/%3~|%~)%{$reset_color%}"
      PROMPT+=' $(git_prompt_info)'

      # ⚠️ No KUBECONFIG export here. There used to be one pointing at
      # ~/.kube/k3s-config — a kubeconfig for k3s-node1 (192.168.178.5), a
      # microVM destroyed in Phase 6. Because this file is interactive-only
      # (.zshrc), it silently beat every other source in an interactive shell
      # while leaving non-interactive `ssh host cmd` alone, so the same machine
      # answered differently depending on how you asked it.
      #
      # Both hosts that need it now get it from somewhere that knows the truth:
      # the Mac renders ~/.kube/config — kubectl's own default — from
      # modules/apps/kubeconfig.nix, and cluster servers get
      # /etc/rancher/k3s/k3s.yaml from modules/system/k3s-cluster.nix. maxdata
      # is both, and this export was shadowing its server config.

      # Clone a repo into a worktree layout:
      #   <name>/.bare      the bare repository
      #   <name>/.git       "gitdir: ./.bare", so git works from <name> itself
      #   <name>/<branch>   worktree of the remote's default branch
      gclone() {
        local url=''${1:-}
        local dir=''${2:-}

        if [[ -z $url ]]; then
          print -u2 "usage: gclone <repository-url> [directory]"
          return 1
        fi

        if [[ -z $dir ]]; then
          dir=''${url##*/}
          dir=''${dir%.git}
        fi

        if [[ -e $dir ]]; then
          print -u2 "gclone: $dir already exists"
          return 1
        fi

        mkdir -p "$dir" || return 1
        if ! git clone --bare "$url" "$dir/.bare"; then
          rmdir "$dir" 2>/dev/null
          return 1
        fi

        print "gitdir: ./.bare" > "$dir/.git"
        git -C "$dir" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" || return 1
        git -C "$dir" fetch origin || return 1

        local base
        base=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null) || base=main
        git -C "$dir" worktree add "$base" || return 1
        git -C "$dir" branch --set-upstream-to="origin/$base" "$base" >/dev/null 2>&1

        print "gclone: $dir ($base)"
      }
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
      man = "batman --paging=always";

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

      #-------------Docker---------------
      dco = "docker compose";
    };
  };
}
