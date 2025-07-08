{
  programs.nvf.settings.vim = {
    debugger = {
      nvim-dap = {
        enable = true;
        ui.enable = true;
      };
    };
    debugMode = {
      enable = false;
      level = 16;
      logFile = "/tmp/nvim.log";
    };
  };
}
