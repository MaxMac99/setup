{
  lib,
  pkgs,
  ...
}: {
  programs.nvf.settings.vim.lsp = {
    enable = true;
    formatOnSave = true;
    lightbulb.enable = true;
    lspkind.enable = true;
    nvim-docs-view.enable = true;
    otter-nvim.enable = true;
    trouble.enable = true;
    inlayHints.enable = true;

    mappings = {
      codeAction = "<leader>ca";
      format = "<leader>f";
      goToDeclaration = "gD";
      goToDefinition = "gd";
      renameSymbol = "<leader>rn";
    };

    servers = {
      "sourcekit-lsp" = {
        cmd = ["xcrun" "sourcekit-lsp"];
        filetypes = ["swift"];
        root_dir = lib.generators.mkLuaInline ''
          function(buf_nr, on_dir)
            local util = require("lspconfig.util")
            on_dir(util.root_pattern 'buildServer.json'(filename)
              or util.root_pattern('*.xcodeproj', '*.xcworkspace')(filename)
              -- better to keep it at the end, because some modularized apps contain multiple Package.swift files
              or util.root_pattern('compile_commands.json', 'Package.swift')(filename)
              or vim.fs.dirname(vim.fs.find('.git', { path = filename, upward = true })[1]))
          end
        '';
      };
      "vue_ls" = {
        cmd = ["${pkgs.vue-language-server}/bin/vue-language-server" "--stdio"];
        filetypes = ["typescript" "javascript" "javascriptreact" "typescriptreact" "vue"];
        init_options = {
          vue = {
            hybridMode = false;
          };
        };
        settings = {
          typescript = {
            tsdk = "${pkgs.typescript-language-server}/lib";
            inlayHints = {
              enumMemberValues.enabled = true;
              functionLikeReturnTypes.enabled = true;
              propertyDeclarationTypes.enabled = true;
              parameterTypes = {
                enabled = true;
                suppressWhenArgumentMatchesName = true;
              };
              variableTypes = {
                enabled = true;
              };
            };
          };
        };
      };
    };
  };
}
