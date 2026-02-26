{pkgs, ...}: {
  programs.nvf.settings.vim.formatter = {
    conform-nvim = {
      enable = true;
      setupOpts = {
        formatters_by_ft = {
          "nix" = ["alejandra"];
          "vue" = ["prettier"];
        };
        formatters = {
          "alejandra" = {
            "command" = "${pkgs.alejandra}/bin/alejandra";
          };
        };
      };
    };
  };
}
