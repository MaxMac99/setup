{lib, ...}: {
  programs.nvf.settings.vim.filetree = {
    neo-tree = {
      enable = true;
      setupOpts = {
        enable_diagnostics = true;
        enable_git_status = true;
        enable_modified_markers = true;
        enable_refresh_on_write = true;
        auto_clean_after_session_restore = true;
        close_if_last_window = true;
        event_handlers = [
          {
            event = "file_open_requested";
            handler = lib.generators.mkLuaInline ''
              function ()
                require('neo-tree.command').execute({ action = "close" })
              end
            '';
          }
        ];
        filesystem = {
          follow_current_file = {
            enabled = true;
            leave_dirs_open = true;
          };
          filtered_items = {
            hide_dotfiles = false;
            hide_gitignored = false;
            hide_by_name = [
              ".DS_Store"
              ".git"
            ];
          };
          window = {
            mappings = {
              "h" = lib.generators.mkLuaInline ''
                function(state)
                  local node = state.tree:get_node()
                  if node.type == "directory" and node:is_expanded() then
                    require('neo-tree.sources.filesystem').toggle_directory(state, node)
                  else
                    require('neo-tree.ui.renderer').focus_node(state, node:get_parent_id())
                  end
                end
              '';
              "l" = lib.generators.mkLuaInline ''
                function(state)
                  local node = state.tree:get_node()
                  if node.type == 'directory' then
                    if not node:is_expanded() then
                      require('neo-tree.sources.filesystem').toggle_directory(state, node)
                    else
                      require('neo-tree.ui.renderer').focus_node(state, node:get_child_ids()[1])
                    end
                  end
                end
              '';
            };
          };
        };
      };
    };
  };
}
