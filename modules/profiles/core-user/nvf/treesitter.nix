{pkgs, ...}: {
  programs.nvf.settings.vim.treesitter = {
    enable = true;
    autotagHtml = true;
    context = {
      enable = true;
      setupOpts = {
        mode = "topline";
        separator = null;
      };
    };
    highlight.enable = true;
    indent.enable = false;
    grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      vue
      swift
      # Common base languages for jinja templates (see jinja.nix), not
      # otherwise pulled in by vim.languages.*.
      dockerfile
      ini
      json
      toml
      xml
    ];
  };
}
