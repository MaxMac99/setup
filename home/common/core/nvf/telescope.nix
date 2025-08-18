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
      findProjects = "<leader>sp";
      gitBranches = "<leader>svb";
      gitBufferCommits = "<leader>svcb";
      gitCommits = "<leader>svcw";
      gitStash = "<leader>svx";
      gitStatus = "<leader>svs";
      lspDefinitions = "<leader>sld";
      lspDocumentSymbols = "<leader>slsd";
      lspImplementations = "<leader>sli";
      lspReferences = "<leader>slr";
      lspTypeDefinitions = "<leader>slt";
      lspWorkspaceSymbols = "<leader>slsw";
      open = "<leader>so";
      treesitter = "<leader>st";
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
