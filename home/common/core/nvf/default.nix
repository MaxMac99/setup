{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    inputs.nvf.homeManagerModules.nvf
    ./ai.nix
    ./autocomplete.nix
    ./autopairs.nix
    ./binds.nix
    ./comments.nix
    ./debugger.nix
    ./filetree.nix
    ./formatter.nix
    ./git.nix
    ./keymaps.nix
    ./languages.nix
    ./lsp.nix
    ./persisted.nix
    ./tabline.nix
    ./telescope.nix
    ./treesitter.nix
    ./ui.nix
    ./utility.nix
    ./visuals.nix
    ./xcode
  ];

  programs.nvf = {
    enable = true;
    settings.vim = {
      mini.ai = {
        enable = true;
      };
      mini.icons.enable = true;

      minimap.codewindow.enable = true;

      notes = {
        todo-comments.enable = true;
      };

      notify = {
        nvim-notify.enable = true;
      };

      options = {
        breakindent = true;
        cursorline = true;
        hidden = true;
        hlsearch = true;
        inccommand = "split";
        incsearch = true;
        laststatus = 3;
        linebreak = true;
        list = true;
        listchars = "tab:» ,trail:·,extends:>,precedes:<,nbsp:␣";
        ruler = true;
        scrolloff = 5;
        shiftwidth = 4;
        tabstop = 4;
        visualbell = true;
      };

      searchCase = "smart";

      snippets = {
        luasnip.enable = true;
      };

      spellcheck = {
        enable = true;
        languages = [
          "en"
          "de"
        ];
      };

      statusline = {
        lualine.enable = true;
      };

      syntaxHighlighting = true;

      terminal.toggleterm = {
        enable = true;
        lazygit.enable = true;
      };

      theme = {
        enable = true;
        name = "onedark";
        style = "deep";
      };

      undoFile.enable = true;
    };
  };
}
