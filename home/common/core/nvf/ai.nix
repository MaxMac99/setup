{pkgs, ...}: {
  programs.nvf.settings.vim = {
    assistant = {
      copilot = {
        enable = true;
        cmp.enable = false;
        mappings = {
          panel = {
            accept = null;
            jumpNext = null;
            jumpPrev = null;
            open = null;
            refresh = null;
          };
          suggestion = {
            accept = null;
            acceptLine = null;
            acceptWord = null;
            dismiss = null;
            next = null;
            prev = null;
          };
        };
      };
    };
    lazy.plugins = {
      "CopilotChat.nvim" = {
        package = pkgs.vimPlugins.CopilotChat-nvim;
        setupModule = "CopilotChat";
        lazy = false;
      };
    };
  };
}
