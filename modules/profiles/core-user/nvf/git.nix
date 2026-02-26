{
  programs.nvf.settings.vim.git = {
    enable = true;
    git-conflict.enable = false;
    gitsigns = {
      enable = true;
      codeActions.enable = false;
      mappings = {
        blameLine = "<leader>gB";
        diffProject = "<leader>gD";
        diffThis = "<leader>gd";
        previewHunk = "<leader>gP";
        resetBuffer = "<leader>gR";
        resetHunk = "<leader>gr";
        stageBuffer = "<leader>gS";
        stageHunk = "<leader>gs";
        toggleBlame = "<leader>gb";
        toggleDeleted = "<leader>gq";
        undoStageHunk = "<leader>gu";
      };
    };
  };
}
