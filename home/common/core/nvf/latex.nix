{pkgs, ...}: {
  programs.nvf.settings.vim = {
    extraPackages = with pkgs; [
      (texlive.combine {
        inherit
          (texlive)
          scheme-medium
          latexmk
          ;
      })
      texlab # Optional: LSP server for additional features
    ];
    extraPlugins = {
      vimtex = {
        package = pkgs.vimPlugins.vimtex;
        setup = ''
          -- Set tex flavor to LaTeX
          vim.g.tex_flavor = 'latex'

          -- PDF viewer configuration for macOS
          vim.g.vimtex_view_method = 'skim'
          vim.g.vimtex_view_skim_sync = 1       -- Forward search after compilation
          vim.g.vimtex_view_skim_activate = 1   -- Focus Skim after viewing

          -- Compiler configuration
          vim.g.vimtex_compiler_method = 'latexmk'
          vim.g.vimtex_compiler_latexmk = {
            callback = 1,
            continuous = 1,
            executable = 'latexmk',
            options = {
              '-verbose',
              '-file-line-error',
              '-synctex=1',
              '-interaction=nonstopmode',
              '-pdf',
            },
          }

          -- Quickfix settings
          vim.g.vimtex_quickfix_mode = 2  -- Auto-open but don't jump to first error

          -- Disable VimTeX's insert mode mappings (recommended if using snippets)
          vim.g.vimtex_imaps_enabled = 0

          -- Table of contents configuration
          vim.g.vimtex_toc_config = {
            name = 'TOC',
            layers = {'content', 'todo', 'include'},
            split_width = 50,
            show_help = 1,
            show_numbers = 1,
          }
        '';
      };
    };
  };
}
