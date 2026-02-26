{
  lib,
  pkgs,
  ...
}: {
  programs.nvf.settings.vim.lazy.plugins = {
    "persisted.nvim" = {
      package = pkgs.vimPlugins.persisted-nvim;
      setupModule = "persisted";
      lazy = false;
      setupOpts = {
        autoload = true;
        use_git_branch = true;
        on_autoload_no_session = lib.generators.mkLuaInline ''
          function()
            vim.notify("No existing session to load")
          end
        '';
      };
    };
  };
}
