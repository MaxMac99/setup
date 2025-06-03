{
  programs.nixvim = {
    plugins.persisted = {
      enable = true;
      settings = {
        autoload = true;
        use_git_branch = true;
        on_autoload_no_session.__raw = ''
          function()
            vim.notify("No existing session to load")
          end
        '';
      };
    };
    keymaps = [
      {
        mode = "n";
        key = "<leader>sp";
        action = "<Cmd>Telescope persisted<CR>";
        options = {
          desc = "[S]earch [P]ersisted sessions";
        };
      }
    ];
  };
}
