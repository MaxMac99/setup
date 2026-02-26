{lib, ...}: {
  programs.nvf.settings.vim.tabline = {
    nvimBufferline = {
      enable = true;
      mappings = {
        closeCurrent = "<leader>xx";
        cycleNext = "<Tab>";
        cyclePrevious = "<S-Tab>";
      };
      setupOpts.options = {
        buffer_close_icon = "󰅖";
        close_icon = " ";
        hover.enabled = false;
        numbers = "none";
        left_trunc_marker = " ";
        right_trunc_marker = " ";
        indicator.style = "underline";
        max_name_length = 22;
        sort_by = "insert_at_end";
        offsets = [
          {
            filetype = "neo-tree";
            text = lib.generators.mkLuaInline ''
              function()
                return vim.fn.getcwd()
              end
            '';
            highlight = "Directory";
            text_align = "left";
            separator = true;
          }
        ];
        tab_size = 23;
      };
    };
  };
}
