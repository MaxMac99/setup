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
        setupOpts = {
          copilot_node_command = "${pkgs.nodejs-slim.out}/bin/node";
        };
      };
    };
    lazy.plugins = {
      "CopilotChat.nvim" = {
        package = pkgs.vimPlugins.CopilotChat-nvim;
        setupModule = "CopilotChat";
        lazy = false;
      };
      "claudecode.nvim" = {
        package = pkgs.vimPlugins.claudecode-nvim;
        setupModule = "claudecode";
        lazy = false;
      };
    };
    extraPackages = with pkgs; [
      nodejs-slim
      gh
      lynx
      lua51Packages.tiktoken_core
    ];
  };
}
