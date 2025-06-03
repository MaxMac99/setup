{ ... }:

{
  programs.zed-editor = {
    enable = true;
    extensions = [ "nix" "dockerfile" "toml" "log" "docker-compose" "env" ];
    userSettings = {
      autosave = "on_focus_change";
      base_keymap = "JetBrains";
      tabs = {
        close_position = "left";
        file_icons = true;
        git_status = true;
      };
      search = {
        regex = true;
      };
      vim_mode = true;
      features = {
        inline_completion_provider = "copilot";
      };
    };
  };
}
