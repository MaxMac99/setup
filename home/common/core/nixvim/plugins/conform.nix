# Autoformat
{ lib
, pkgs
, ...
}:
{
  programs.nixvim.plugins.conform-nvim = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings = {
        event = "BufWritePre";
        cmd = "ConformInfo";
        keys = [
          {
            mode = "";
            __unkeyed-1 = "<leader>f";
            __unkeyed-2.__raw = ''
              function()
                  require('conform').format { async = true, lsp_fallback = true }
              end
            '';
            desc = "[F]ormat buffer";
          }
        ];
      };
    };
    settings = {
      notify_on_error = true;
      format_on_save = ''
        function (bufnr)
            local disable_filetypes = { c = true, cpp = true }
            return {
                timeout_ms = 500,
                lsp_fallback = not disable_filetypes[vim.bo[bufnr].filetype],
            }
        end
      '';
      formatters_by_ft = {
        lua = [
          "stylua"
        ];
        swift = [
          "swiftformat"
        ];
        javascript = [
          "prettier"
          "eslint_d"
        ];
        typescript = [
          "prettier"
          "eslint_d"
        ];
        nix = [
          "nixpkgs-fmt"
        ];
      };
      formatters = {
        stylua = {
          command = lib.getExe pkgs.stylua;
        };
        prettier = {
          command = lib.getExe pkgs.nodePackages.prettier;
        };
        eslint_d = {
          command = lib.getExe pkgs.nodePackages.eslint_d;
          args = [ "--fix-to-stdout" "--stdin" "--stdin-filename" "$FILENAME" ];
          stdin = true;
          timeoutMs = 5000;
        };
        swiftformat = {
          command = lib.getExe pkgs.swiftformat;
        };
        nixpkgs-fmt = {
          command = lib.getExe pkgs.nixpkgs-fmt;
        };
      };
    };
  };
}
