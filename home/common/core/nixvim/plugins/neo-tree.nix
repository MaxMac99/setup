{
  programs.nixvim = {
    plugins.neo-tree = {
      enable = true;
      enableDiagnostics = true;
      enableGitStatus = true;
      enableModifiedMarkers = true;
      enableRefreshOnWrite = true;
      closeIfLastWindow = true;
      eventHandlers = {
        "file_open_requested" = ''
          function ()
            require('neo-tree.command').execute({ action = "close" })
          end
        '';
      };
      filesystem.filteredItems = {
        hideDotfiles = false;
        hideGitignored = false;
        hideByName = [
          ".DS_Store"
          ".git"
        ];
      };
      filesystem.window.mappings = {
        "h".__raw = ''
          function(state)
              local node = state.tree:get_node()
              if node.type == "directory" and node:is_expanded() then
                  require('neo-tree.sources.filesystem').toggle_directory(state, node)
              else
                  require('neo-tree.ui.renderer').focus_node(state, node:get_parent_id())
              end
          end
        '';
        "l".__raw = ''
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
    keymaps = [
      {
        mode = "n";
        key = "<C-e>";
        action = "<cmd>Neotree toggle<CR>";
        options = {
          silent = true;
          desc = "Explorer NeoTree (cwd)";
        };
      }
    ];
  };
}

