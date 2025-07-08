{
  programs.nvf.settings.vim.keymaps = [
    {
      mode = "";
      key = "H";
      action = "^";
    }
    {
      mode = "";
      key = "L";
      action = "$";
    }
    {
      mode = "";
      key = "J";
      action = "}";
    }
    {
      mode = "";
      key = "K";
      action = "{";
    }
    {
      mode = "";
      key = "<C-h>";
      action = "<C-w><C-h>";
      desc = "Move to left window";
    }
    {
      mode = "";
      key = "<C-l>";
      action = "<C-w><C-l>";
      desc = "Move to right window";
    }
    {
      mode = "";
      key = "<C-j>";
      action = "<C-w><C-j>";
      desc = "Move to lower window";
    }
    {
      mode = "";
      key = "<C-k>";
      action = "<C-w><C-k>";
      desc = "Move to upper window";
    }
    {
      mode = "n";
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
    }
    {
      mode = "n";
      key = "<C-e>";
      action = "<cmd>Neotree toggle<CR>";
      desc = "Explorer NeoTree (cwd)";
    }
    {
      mode = "n";
      key = "<leader>sp";
      action = "<cmd>Telescope persisted<CR>";
      desc = "[S]earch [P]ersisted sessions";
    }
  ];
}
