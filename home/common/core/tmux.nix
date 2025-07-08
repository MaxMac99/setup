{pkgs, ...}: let
  tokyo-theme = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tokyo-night";
    version = "1.5.5";
    rtpFilePath = "tokyo-night.tmux";
    src = pkgs.fetchFromGitHub {
      owner = "janoamaral";
      repo = "tokyo-night-tmux";
      rev = "v1.5.5";
      sha256 = "sha256-ATaSfJSg/Hhsd4LwoUgHkAApcWZV3O3kLOn61r1Vbag=";
    };
  };
in {
  home.packages = [
    pkgs.nowplaying-cli
  ];
  programs.tmux = {
    enable = true;
    clock24 = true;
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    newSession = true;
    shortcut = "a";
    terminal = "screen-256color";
    escapeTime = 300;
    focusEvents = true;
    extraConfig = ''
      # split panes horizontal by -
      bind - split-window -v
      unbind '"'

      # Emulate scrolling by sending up and down keys if these commands are running in the pane
      tmux_commands_with_legacy_scroll="nano less more man"

      bind-key -T root WheelUpPane \
        if-shell -Ft= '#{?mouse_any_flag,1,#{pane_in_mode}}' \
          'send -Mt=' \
          'if-shell -t= "#{?alternate_on,true,false} || echo \"#{tmux_commands_with_legacy_scroll}\" | grep -q \"#{pane_current_command}\"" \
            "send -t= Up Up Up" "copy-mode -et="'

      bind-key -T root WheelDownPane \
        if-shell -Ft = '#{?pane_in_mode,1,#{mouse_any_flag}}' \
          'send -Mt=' \
          'if-shell -t= "#{?alternate_on,true,false} || echo \"#{tmux_commands_with_legacy_scroll}\" | grep -q \"#{pane_current_command}\"" \
            "send -t= Down Down Down" "send -Mt="'
    '';
    plugins = with pkgs.tmuxPlugins; [
      cpu
      yank
      pain-control
      vim-tmux-navigator
      {
        plugin = tokyo-theme;
        extraConfig = ''
          set -g @tokyo-night-tmux_show_music 1
        '';
      }
    ];
  };
}
