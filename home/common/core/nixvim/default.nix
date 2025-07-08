{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixvim.homeManagerModules.nixvim
    ./keymaps.nix
    ./plugins
  ];

  programs.nixvim = {
    enable = true;
    enableMan = true;

    clipboard.register = "unnamedplus";

    colorschemes.tokyonight = {
      enable = true;
      settings.on_colors = ''
        function(colors)
          colors.border = "cyan"
        end
      '';
    };

    globals = {
      mapleader = " ";
      maplocalleader = " ";
      have_nerd_font = true;
      tokyonight_colors.border = "cyan";
    };

    opts = {
      hidden = true;
      number = true;
      relativenumber = true;
      showmode = true;
      autoread = true;
      mouse = "a";
      ruler = true;
      visualbell = true;
      breakindent = true;
      undofile = true;

      wrap = false;
      linebreak = true;

      # Redirect temp files
      backupdir = "$HOME/.vim/backup//,/tmp//,.";
      writebackup = false;
      directory = "$HOME/.vim/swap//,/tmp//,.";

      # Folds
      foldmethod = "indent";
      foldnestmax = 3;
      foldenable = false;

      # Splits
      splitright = true;
      splitbelow = true;

      # Search
      incsearch = true;
      hlsearch = true;
      ignorecase = true;
      smartcase = true;
      inccommand = "split";
      laststatus = 3;

      # Whitespaces
      list = true;
      listchars = {
        tab = "» ";
        trail = "·";
        extends = ">";
        precedes = "<";
        nbsp = "␣";
      };

      cursorline = true;

      scrolloff = 5;
      sidescrolloff = 15;
      sidescroll = 1;
    };
  };
}
