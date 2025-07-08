{
  programs.nixvim.keymaps = [
    {
      mode = [""];
      key = "H";
      action = "^";
    }
    {
      mode = [""];
      key = "L";
      action = "$";
    }
    {
      mode = [""];
      key = "J";
      action = "}";
    }
    {
      mode = [""];
      key = "K";
      action = "{";
    }
    {
      mode = [""];
      key = "<C-h>";
      action = "<C-w><C-h>";
      options.desc = "Move to left window";
    }
    {
      mode = [""];
      key = "<C-l>";
      action = "<C-w><C-l>";
      options.desc = "Move to right window";
    }
    {
      mode = [""];
      key = "<C-j>";
      action = "<C-w><C-j>";
      options.desc = "Move to lower window";
    }
    {
      mode = [""];
      key = "<C-k>";
      action = "<C-w><C-k>";
      options.desc = "Move to upper window";
    }
    {
      mode = ["n"];
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
    }
    {
      mode = ["t"];
      key = "<Esc><Esc>";
      action = "<C-\\><C-n>";
      options.desc = "Exit terminal mode";
    }
  ];
}
