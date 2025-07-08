{
  hostSpec,
  lib,
  pkgs,
  ...
}: let
  flakeRoot = lib.custom.relativeToRoot "./.";
in {
  programs.nixvim = {
    plugins = {
      lspconfig.enable = true;
    };
    lsp.servers = {
      bashls.enable = true;
      dockerls.enable = true;
      eslint.enable = true;
      # gopls.enable = true;
      java_language_server.enable = true;
      kotlin_language_server.enable = true;
      lua_ls = {
        enable = true;
        settings = {
          Lua = {
            completion = {
              callSnippet = "Replace";
            };
          };
        };
      };
      nixd = {
        enable = true;
        settings = {
          nix = {
            nixpkgs = {
              expr = "import <nixpkgs> { }";
            };
            formatting = {
              command = ["nixfmt"];
            };
            options = {
              nixos = {
                expr = ''
                  let configs = (builtins.getFlake "${flakeRoot}").nixosConfigurations;
                  in (builtins.head (builtins.attrValues configs)).options
                '';
              };
              home_manager = {
                expr = ''
                  (builtins.getFlake "${flakeRoot}").nixosConfigurations.${hostSpec.hostName}.options.home-manager.users.value.${hostSpec.username}
                '';
              };
              darwin = {
                expr = ''
                  let configs = (builtins.getFlake "${flakeRoot}").darwinConfigurations;
                  in (builtins.head (builtins.attrValues configs)).options
                '';
              };
            };
          };
        };
      };
      postgres_lsp.enable = true;
      rust_analyzer.enable = true;
      sourcekit.enable = true;
      ts_ls = {
        enable = true;
        settings = {
          tsserver = {
            filetypes = [
              "javascript"
              "javascriptreact"
              "typescript"
              "typescriptreact"
              "vue"
            ];
            init_options = {
              plugins = [
                {
                  name = "@vue/typescript-plugin";
                  location = "${pkgs.vue-language-server}/bin/vue-language-server";
                  languages = [
                    "vue"
                  ];
                }
              ];
            };
            settings = {
              typescript = {
                tsserver = {
                  useSyntaxServer = false;
                };
                inlayHints = {
                  includeInlayParameterNameHints = "all";
                  includeInlayParameterNameHintsWhenArgumentMatchesName = true;
                  includeInlayFunctionParameterTypeHints = true;
                  includeInlayVariableTypeHints = true;
                  includeInlayVariableTypeHintsWhenTypeMatchesName = true;
                  includeInlayPropertyDeclarationTypeHints = true;
                  includeInlayFunctionLikeReturnTypeHints = true;
                  includeInlayEnumMemberValueHints = true;
                };
              };
            };
          };
        };
      };
      volar = {
        enable = true;
        settings = {
          init_options = {
            vue = {
              hybridMode = false;
            };
          };
          settings = {
            typescript = {
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
      jsonls.enable = true;
      yamlls.enable = true;
      typos_lsp = {
        enable = true;
        settings = {
          init_options = {
            diagnosticSeverity = "Warning";
          };
        };
      };
    };
    lsp.luaConfig.post = builtins.readFile ./lsp-attach.lua;
    keymaps = [
      {
        mode = "n";
        key = "<leader>cd";
        action.__raw = ''
          function()
            vim.diagnostic.open_float(nil, { focusable = true, scope = "cursor" })
          end
        '';
        options = {
          desc = "[C]ode [D]iagnostics";
        };
      }
      {
        mode = "n";
        key = "<leader>ge";
        action.__raw = "vim.diagnostic.goto_next";
        options = {
          desc = "[G]o to [E]rror";
        };
      }
    ];
  };
  home.packages = with pkgs; [
    nodejs
    yarn
    nodePackages.jsonlint
    nodePackages.eslint
    nodePackages.eslint_d
    vscode-js-debug
    nodePackages.vscode-langservers-extracted
  ];
}
