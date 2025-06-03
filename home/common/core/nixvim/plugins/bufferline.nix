{
  programs.nixvim = {
    plugins.bufferline = {
      enable = true;
      settings.options = {
        indicator.style = "underline";
        max_name_length = 22;
        tab_size = 23;
        diagnostics = "nvim_lsp";
        offsets = [
          {
            filetype = "neo-tree";
            text.__raw = ''
              function ()
                return vim.fn.getcwd()
              end
            '';
            highlight = "Directory";
            text_align = "left";
            separator = true;
          }
        ];
        diagnostics_indicator.__raw = ''
          function(_, _, diagnostics_dict, _)
            local s = ' ';
            for e, n in pairs(diagnostics_dict) do
              local sym = e == 'error' and ' ' or (e == 'warning' and ' ' or ' ')
              s = s .. n .. sym
            end
            return s
          end
        '';
      };
    };
    keymaps = [
      {
        mode = "n";
        key = "<leader>xx";
        action.__raw = ''
          function()
            vim.cmd("write")
            vim.cmd("bdelete")
          end
        '';
        options.desc = "Close And Save Buffer";
      }
      {
        mode = "n";
        key = "<tab>";
        action = "<cmd>BufferLineCycleNext<cr>";
        options.desc = "Switch to next buffer";
      }
      {
        mode = "n";
        key = "<S-tab>";
        action = "<cmd>BufferLineCyclePrev<cr>";
        options.desc = "Switch to previous buffer";
      }
    ];
  };
}
