{
  pkgs,
  lib,
  ...
}: {
  programs.nvf.settings.vim.telescope = {
    enable = true;
    mappings = {
      buffers = "<leader>sb";
      diagnostics = "<leader>sd";
      findFiles = "<leader>sf";
      liveGrep = "<leader>sg";
      helpTags = "<leader>sh";
      resume = "<leader>sr";
    };
    extensions = [
      {
        name = "ui-select";
        packages = with pkgs.vimPlugins; [telescope-ui-select-nvim];
        setup = {
          "ui-select" = lib.generators.mkLuaInline ''            {
                        require("telescope.themes").get_dropdown {}
                      }'';
        };
      }
      {
        name = "fzf";
        packages = with pkgs.vimPlugins; [telescope-fzf-native-nvim];
        setup = {fzf = {fuzzy = true;};};
      }
    ];
  };
  home.packages = with pkgs; [
    fd
  ];
}
