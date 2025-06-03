{
  programs.nixvim.plugins.todo-comments = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.events = "VimEnter";
    };
    settings = {
      signs = false;
    };
  };
}
