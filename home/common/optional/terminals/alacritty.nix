{ config, pkgs, ... }:

{
  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 16;
        normal = {
          family = "SFMono Nerd Font";
          style = "Regular";
        };
        italic = {
          family = "SFMono Nerd Font";
          style = "Italic";
        };
        bold = {
          family = "SFMono Nerd Font";
          style = "Bold";
        };
      };
      env = {
        "TERM" = "xterm-256color";
      };
      window = {
        opacity = 1.0;
        startup_mode = "Fullscreen";
        decorations = "Full";
        blur = true;
      };
      # URL highlighting
      hints = {
        enabled = [
          {
            regex = ''(mailto:|gemini:|gopher:|https:|http:|news:|file:|git:|ssh:|ftp:|www)[^\u0000-\u001F\u007F-\u009F<>"\\s{-}\\^⟨⟩`]+'';
            command = "open";
            post_processing = true;
            mouse = {
              enabled = true;
              mods = "Command";
            };
            binding = {
              key = "U";
              mods = "Command|Shift";
            };
          }
        ];
      };
      # Tokyo night theme
      colors = {
        primary = {
          background = "#1a1b26";
          foreground = "#a9b1d6";
        };
        normal = {
          black = "#32344a";
          red = "#f7768e";
          green = "#9ece6a";
          yellow = "#e0af68";
          blue = "#7aa2f7";
          magenta = "#ad8ee6";
          cyan = "#449dab";
          white = "#787c99";
        };
        bright = {
          black = "#444b6a";
          red = "#ff7a93";
          green = "#b9f27c";
          yellow = "#ff9e64";
          blue = "#7da6ff";
          magenta = "#bb9af7";
          cyan = "#0db9d7";
          white = "#acb0d0";
        };
      };
    };
  };
}
