# Zed editor - nixpkgs + HM config
{config, pkgs, ...}: {
  environment.systemPackages = [pkgs.zed-editor];

  home-manager.users.${config.hostSpec.username} = {
    home.packages = with pkgs; [nil nixd];

    programs.zed-editor = {
      enable = true;
      package = null; # Installed via environment.systemPackages
      extensions = ["nix" "dockerfile" "toml" "log" "docker-compose" "env" "rust" "xcode-themes" "tokyo-night" "material-icon-theme"];
      userSettings = {
        # Appearance
        buffer_font_family = "SF Mono";
        buffer_font_size = 15;
        relative_line_numbers = "enabled";
        theme = {
          mode = "system";
          light = "Xcode Default Light";
          dark = "Tokyo Night";
        };
        icon_theme = "Material Icon Theme";

        # Theme overrides for better syntax coloring
        "experimental.theme_overrides" = {
          text = "#bcbec4ff";
          "text.muted" = "#bcbec4ff";
          accents = [
            "#f7768e" # Red
            "#ff9e64" # Orange
            "#e0af68" # Yellow
            "#9ece6a" # Green
            "#7dcfff" # Cyan
            "#bb9af7" # Purple
          ];
          syntax = {
            "property.json_key" = {color = "#7aa2f7";};
            property = {color = "#7aa2f7";};
            "variable.member" = {color = "#9d7cd8";};
            type = {color = "#9d7cd8";};
          };
        };

        # Text & Wrapping
        soft_wrap = "editor_width";
        show_whitespaces = "selection";
        preferred_line_length = 100;
        show_wrap_guides = true;
        wrap_guides = [100];
        indent_guides = {
          enabled = true;
          coloring = "indent_aware";
        };

        # Editor Features
        which_key.enabled = true;
        minimap.show = "always";
        colorize_brackets = true;

        # Inlay Hints
        inlay_hints = {
          enabled = true;
          show_type_hints = true;
          show_parameter_hints = true;
        };

        # Git Integration
        git = {
          inline_blame.enabled = true;
          git_gutter = "tracked_files";
        };

        # Terminal
        terminal = {
          font_family = "SF Mono";
          font_size = 14;
        };

        # Panels & UI
        tab_bar.show = true;
        scrollbar.show = "auto";
        toolbar = {
          breadcrumbs = true;
          quick_actions = true;
        };

        # File Exclusions
        file_scan_exclusions = ["**/.git"];

        # Editor Behavior
        autosave = "on_focus_change";
        base_keymap = "JetBrains";
        tabs = {
          close_position = "left";
          file_icons = true;
          git_status = true;
        };
        search = {regex = true;};
        vim_mode = true;

        # AI Features
        features = {edit_prediction_provider = "copilot";};
        agent_servers = {
          claude = {
            env = {CLAUDE_CODE_EXECUTABLE = pkgs.claude-code;};
          };
        };

        # LSP Configuration
        lsp = {
          rust-analyzer = {
            initialization_options = {
              check = {command = "clippy";};
            };
          };
          nil = {
            initialization_options = {
              formatting = {command = ["nixfmt"];};
            };
          };
        };

        # Language Settings
        languages = {
          Rust = {
            format_on_save = "on";
            formatter = [
              {code_action = "source.organizeImports";}
              {language_server = {name = "rust-analyzer";};}
            ];
          };
          Nix = {format_on_save = "on";};
        };
      };
      userKeymaps = [
        {
          context = "vim_mode == normal && !menu";
          bindings = {space = null;};
        }
        {
          context = "VimControl && !menu";
          bindings = {
            H = "vim::FirstNonWhitespace";
            L = "vim::EndOfLine";
            J = "vim::EndOfParagraph";
            K = "vim::StartOfParagraph";
          };
        }
        {
          context = "VimControl && !menu";
          bindings = {
            "ctrl-h" = "workspace::ActivatePaneLeft";
            "ctrl-l" = "workspace::ActivatePaneRight";
            "ctrl-j" = "workspace::ActivatePaneDown";
            "ctrl-k" = "workspace::ActivatePaneUp";
            "ctrl-o" = "pane::GoBack";
            "ctrl-i" = "pane::GoForward";
          };
        }
        {
          context = "vim_mode == normal && !menu";
          bindings = {
            "ctrl-tab" = "pane::ActivatePreviousItem";
            tab = "pane::ActivateNextItem";
            "ctrl-n" = "editor::SelectNext";
          };
        }
        {
          context = "vim_mode == normal && !menu";
          bindings = {
            "space x x" = "pane::CloseActiveItem";
            "space x a" = "pane::CloseAllItems";
            "space x o" = "pane::CloseOtherItems";
            "space s h" = "pane::SplitDown";
            "space s v" = "pane::SplitRight";
            "space c" = "editor::ToggleComments";
            "space shift-c" = "editor::ToggleComments";
            "space q f" = "editor::ToggleCodeActions";
            "space q e" = "editor::Hover";
            "space f c" = "editor::Format";
            "space o i" = "editor::OrganizeImports";
            "space r n" = "editor::Rename";
            "space r e" = "editor::ToggleCodeActions";
            "space h c" = "editor::FindAllReferences";
            "space d b" = "editor::ToggleBreakpoint";
            "space r c" = "task::Spawn";
            "space r r" = "task::Rerun";
            "space t t" = "terminal_panel::ToggleFocus";
            "space t c" = "terminal_panel::ToggleFocus";
            "space shift-a" = "command_palette::Toggle";
            "space a f" = "agent::ToggleFocus";
            "space a o" = "agent::AllowOnce";
            "space a m" = "agent::CycleModeSelector";
            "space a c" = "workspace::ToggleRightDock";
            "g a" = "file_finder::Toggle";
            "g c" = "project_symbols::Toggle";
            "g f" = "file_finder::Toggle";
            "g s" = "project_symbols::Toggle";
            "g shift-t" = "pane::DeploySearch";
            "g o" = "editor::GoToDefinition";
            "g d" = "editor::GoToDefinition";
            "g shift-d" = "editor::GoToTypeDefinition";
            "g r" = "editor::FindAllReferences";
            "g shift-r" = "editor::FindAllReferences";
            "g i" = "editor::GoToImplementation";
            "g shift-i" = "editor::Hover";
            "g n" = "outline::Toggle";
            "g m" = ["workspace::SendKeystrokes" "%"];
            "space ctrl-n" = "editor::SelectAllMatches";
          };
        }
        {
          context = "vim_mode == visual && !menu";
          bindings = {
            "ctrl-x" = "editor::SelectNext";
            "space c" = "editor::ToggleComments";
          };
        }
        {
          context = "Editor";
          bindings = {
            "ctrl-o" = "pane::GoBack";
            "ctrl-i" = "pane::GoForward";
          };
        }
        {
          context = "BufferSearchBar";
          bindings = {
            "ctrl-o" = "pane::GoBack";
            escape = "buffer_search::Dismiss";
            "ctrl-c" = "buffer_search::Dismiss";
          };
        }
        {
          context = "ProjectSearchView";
          bindings = {"ctrl-o" = "pane::GoBack";};
        }
      ];
    };
  };
}