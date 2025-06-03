{ pkgs
, ...
}:
let
  typescriptConfigurations = [{
    type = "pwa-node";
    request = "launch";
    name = "Launch file";
    program = "\${file}";
    cwd = "\${workspaceFolder}";
  }];
in
{
  programs.nixvim = {
    plugins = {
      dap = {
        enable = true;
        configurations = {
          typescript = typescriptConfigurations;
          javascript = typescriptConfigurations;
          vue = typescriptConfigurations;
        };
        adapters.servers = {
          "pwa-node" = {
            port = 9229;
            host = "localhost";
            executable = {
              command = "node";
              args = [
                "${pkgs.vscode-js-debug}/lib/node_modules/js-debug/dist/src/dapDebugServer.js"
                "9229"
              ];
            };
          };
        };
      };
      dap-ui = {
        enable = true;
      };
    };
    keymaps = [
      {
        key = "<leader>dd";
        action = "<cmd>DapContinue<cr>";
        options.desc = " Continue";
      }
      {
        key = "<leader>do";
        action = "<cmd>DapStepOver<cr>";
        options.desc = " StepOver";
      }
      {
        key = "<leader>dr";
        action = "<cmd>DapRerun<cr>";
        options.desc = " Rerun";
      }
      {
        key = "<leader>db";
        action = "<cmd>DapToggleBreakpoint<cr>";
        options.desc = " Toggle Breakpoints";
      }
      {
        key = "<leader>dB";
        action = "<cmd>lua require('dap').clear_breakpoints()<cr>";
        options.desc = " Clear Breakpoints";
      }
      {
        key = "<leader>dc";
        action = "<cmd>DapContinue<cr>";
        options.desc = " Continue";
      }
      {
        key = "<leader>ds";
        action = "<cmd>DapStepInto<cr>";
        options.desc = " Step Into";
      }
      {
        key = "<leader>dS";
        action = "<cmd>DapStepOut<cr>";
        options.desc = " StepOut";
      }
      {
        key = "<leader>dD";
        action = "<cmd>DapTerminate<cr>";
        options.desc = "󰈆 Terminate";
      }
      {
        key = "<leader>fd";
        action = "<cmd>lua _G.FUNCS.dapui_focus_or_close()<cr>";
        options.desc = " Toggle Dap UI";
      }
    ];
    extraConfigLua = ''
      local dapUIFileTypes = { "dapui_scopes", "dapui_breakpoints", "dapui_stacks", "dapui_watches", "dapui_console", "dap-repl" }
    '';

    # _G.FUNCS.check_dapui_visible = function()
    #   local dapFiletypeSet = {}
    #   for _, ft in ipairs(dapUIFileTypes) do
    #     dapFiletypeSet[ft] = true
    #   end
    #   for _, win in ipairs(vim.api.nvim_list_wins()) do
    #     local buf = vim.api.nvim_win_get_buf(win)
    #     local ft = vim.api.nvim_buf_get_option(buf, "filetype")
    #     if dapFiletypeSet[ft] then
    #       return true
    #     end
    #   end
    #   return false
    # end

    #   _G.FUNCS.check_dapui_focused = function()
    #     local dapui = require("dapui")
    #     -- if focus dapUI -> close dapUI
    #     for _, ft in ipairs(dapUIFileTypes) do
    #       if vim.bo.filetype == ft then
    #         -- dapui.close()
    #         return true
    #       end
    #     end
    #     return false
    #   end

    #   _G.FUNCS.dapui_focus_or_close = function()
    #     local dapui = require("dapui")
    #     if _G.FUNCS.check_dapui_focused() then
    #       dapui.close()
    #       return
    #     end


    #     -- dapUI does not exists or not focused
    #     -- close neotree first
    #     for _, win in ipairs(vim.api.nvim_list_wins()) do
    #       local buf = vim.api.nvim_win_get_buf(win)
    #       local ft = vim.api.nvim_buf_get_option(buf, "filetype")
    #       if ft == 'neo-tree' then
    #         vim.cmd("Neotree close")
    #       end
    #     end

    #     -- open dapui if not exists
    #     dapui.open()
    #     -- focus the first openning dapui_scopes
    #     vim.defer_fn(function()
    #       for _, win in ipairs(vim.api.nvim_list_wins()) do
    #         local buf = vim.api.nvim_win_get_buf(win)
    #         local ft = vim.api.nvim_buf_get_option(buf, "filetype")
    #         if ft == "dapui_scopes" then
    #           vim.api.nvim_set_current_win(win)
    #           break
    #         end
    #       end
    #     end, 100)
    #   end


    #   _G.FUNCS.switch_dapui_window = function()
    #     local dapui_filetypes = {
    #       ["dapui_scopes"] = true,
    #       ["dapui_breakpoints"] = true,
    #       ["dapui_stacks"] = true,
    #       ["dapui_watches"] = true,
    #       ["dapui_console"] = true,
    #       ["dap-repl"] = true,
    #     }

    #     local current_win = vim.api.nvim_get_current_win()
    #     local current_buf = vim.api.nvim_win_get_buf(current_win)
    #     local current_ft = vim.api.nvim_buf_get_option(current_buf, "filetype")

    #     -- Only act if current window is DAP UI
    #     if not dapui_filetypes[current_ft] then
    #       return
    #     end

    #     local wins = vim.api.nvim_list_wins()
    #     local dapui_wins = {}

    #     -- Collect all DAP UI windows
    #     for _, win in ipairs(wins) do
    #       local buf = vim.api.nvim_win_get_buf(win)
    #       local ft = vim.api.nvim_buf_get_option(buf, "filetype")
    #       if dapui_filetypes[ft] then
    #         table.insert(dapui_wins, win)
    #       end
    #     end

    #     -- Sort dapui windows by window ID for consistency
    #     table.sort(dapui_wins)

    #     -- Find current index
    #     local current_index = nil
    #     for i, win in ipairs(dapui_wins) do
    #       if win == current_win then
    #         current_index = i
    #         break
    #       end
    #     end

    #     -- Move to next window (circular)
    #     if current_index then
    #       local next_index = (current_index % #dapui_wins) + 1
    #       vim.api.nvim_set_current_win(dapui_wins[next_index])
    #     end
    #   end


    #   vim.api.nvim_create_autocmd("FileType", {
    #     pattern = {
    #       "dapui_scopes",
    #       "dapui_breakpoints",
    #       "dapui_stacks",
    #       "dapui_watches",
    #       "dapui_console",
    #       "dap-repl",
    #     },
    #     callback = function()
    #       vim.keymap.set("n", "<Tab>", function()
    #         _G.FUNCS.switch_dapui_window()
    #       end, { buffer = true, noremap = true, silent = true })
    #     end,
    #   })

    extraConfigLuaPost = ''
      local dap, dapui = require("dap"), require("dapui")
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end

      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end

      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    '';
  };
}
