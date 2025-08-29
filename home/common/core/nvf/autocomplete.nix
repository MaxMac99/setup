{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim.autocomplete = {
    blink-cmp = {
      enable = true;
      friendly-snippets.enable = true;
      mappings = {
        close = "<C-q>";
        confirm = "<Tab>";
        next = "<C-n>";
        previous = "<C-p>";
      };
      setupOpts = {
        appearance.kind_icons = lib.mkForce (lib.generators.mkLuaInline ''
          require("lspkind").presets.codicons
        '');
        fuzzy.implementation = "prefer_rust_with_warning";
        sources.default = [
          "lsp"
          "path"
          "snippets"
          "buffer"
        ];
        sources.providers = {
          copilot = {
            name = "copilot";
            module = "blink-copilot";
            score_offset = 100;
            async = true;
          };
        };
        completion.menu.draw.columns = lib.generators.mkLuaInline ''          {
                    { 'kind_icon' },
                    { 'label', 'label_description', gap = 2 },
                    { 'kind' },
                    { 'source_name' }
                  }'';
      };
      sourcePlugins = {
        copilot = {
          enable = true;
          package = pkgs.vimPlugins.blink-copilot;
          module = "blink-copilot";
        };
      };
    };
  };
}
