{
  programs.nixvim = {
    plugins.lazygit = {
      enable = true;
    };
    keymaps = [
      {
        key = "<leader>gg";
        action = "<Cmd>LazyGit<CR>";
        mode = "n";
        options.desc = "Open LazyGit";
      }
    ];
  };
}
