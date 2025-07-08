{
  programs.nixvim.plugins.which-key = {
    enable = true;
    settings = {
      spec = [
        {
          __unkeyed = "<leader>c";
          group = "[C]ode";
        }
        {
          __unkeyed = "<leader>d";
          group = "[D]ocument";
        }
        {
          __unkeyed = "<leader>r";
          group = "[R]ename";
        }
        {
          __unkeyed = "<leader>s";
          group = "[S]earch";
        }
        {
          __unkeyed = "<leader>w";
          group = "[W]orkspace";
        }
        {
          __unkeyed = "<leader>t";
          group = "[T]oggle";
        }
        {
          __unkeyed = "<leader>h";
          group = "Git [H]unk";
          mode = ["n" "v"];
        }
      ];
    };
  };
}
