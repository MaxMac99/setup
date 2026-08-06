{
  programs.nvf.settings.vim.utility = {
    diffview-nvim.enable = true;
    multicursors.enable = true;
    preview = {
      # Floating terminal window, rendered by glow.
      glow = {
        enable = true;
        mappings.openPreview = "<leader>mp";
      };
      # Browser tab with live reload, see <leader>mb in keymaps.nix.
      markdownPreview.enable = true;
    };
    snacks-nvim = {
      enable = true;
      setupOpts = {
        bigfile.enabled = true;
        dashboard.enabled = false;
        image.enabled = true;
      };
    };
  };
}
