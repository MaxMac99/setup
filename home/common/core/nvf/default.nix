{
  inputs,
  lib,
  config,
  hostSpec,
  ...
}: {
  imports =
    [
      inputs.nvf.homeManagerModules.nvf
      ./autocomplete.nix
      ./autopairs.nix
      ./binds.nix
      ./comments.nix
      ./filetree.nix
      ./git.nix
      ./keymaps.nix
      ./persisted.nix
      ./tabline.nix
      ./telescope.nix
      ./treesitter.nix
    ]
    ++ lib.optionals (!hostSpec.isMinimal) [
      ./ai.nix
      ./debugger.nix
      ./formatter.nix
      ./languages.nix
      ./lsp.nix
      ./ui.nix
      ./utility.nix
      ./visuals.nix
    ]
    ++ lib.optionals hostSpec.isDarwin [
      ./latex.nix
      ./xcode
    ];

  programs.nvf = {
    enable = true;
    settings.vim = {
      autocmds = [
        {
          enable = true;
          event = ["TextYankPost"];
          callback = lib.generators.mkLuaInline ''
            function()
            vim.highlight.on_yank()
            end
          '';
        }
        {
          enable = true;
          event = ["FocusGained" "BufEnter" "CursorHold" "CursorHoldI"];
          callback = lib.generators.mkLuaInline ''
            function()
            if vim.fn.mode() ~= 'c' then
              vim.cmd('checktime')
            end
            end
          '';
        }
        {
          enable = true;
          event = ["FileChangedShellPost"];
          callback = lib.generators.mkLuaInline ''
            function()
            vim.notify("File changed on disk. Buffer reloaded!", vim.log.levels.WARN)
            end
          '';
        }
      ];

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
        autoread = true;
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
