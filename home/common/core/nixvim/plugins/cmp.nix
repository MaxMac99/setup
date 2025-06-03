# Autocompletion
{
  programs.nixvim.plugins = {
    lspkind.enable = true;
    cmp = {
      enable = true;
      autoEnableSources = true;
      settings = {
        snippet.expand = ''
          function(args)
              require("luasnip").lsp_expand(args.body)
          end
        '';
        completion.completeopt = "menu,menuone,noinsert";
        mapping = {
          "<C-j>" = "cmp.mapping.select_next_item()";
          "<C-k>" = "cmp.mapping.select_prev_item()";
          "<C-b>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<Tab>" = "cmp.mapping.confirm { select = true }";
          "<C-Space>" = "cmp.mapping.complete {}";
          "<C-l>" = ''
            cmp.mapping(function()
                if luasnip.expand_or_jumpable() then
                    luasnip.expand_or_jump()
                end
            end, { "i", "s" })
          '';
          "<C-h>" = ''
            cmp.mapping(function()
                if luasnip.locally_jumpable(-1) then
                    luasnip.jump(-1)
                end
            end, { "i", "s" })
          '';
        };
        sources = [
          { name = "cmp-nvim-lsp"; }
          { name = "async_path"; }
          { name = "nvim_lsp_signature_help"; }
          { name = "nvim_lsp"; keyword_length = 3; }
          { name = "nvim_lua"; keyword_length = 2; }
          { name = "luasnip"; }
          { name = "copilot"; }
          { name = "buffer"; keyword_length = 2; }
        ];
      };
    };
    cmp-nvim-lsp.enable = true;
    cmp-nvim-lua.enable = true;
    cmp-async-path.enable = true;
    cmp-buffer.enable = true;
    cmp_luasnip.enable = true;
    cmp-nvim-lsp-signature-help.enable = true;
    luasnip.enable = true;
  };
}
