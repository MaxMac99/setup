{
  programs.nixvim.plugins = {
    copilot-lua = {
      enable = true;
      lazyLoad = {
        enable = true;
        settings.event = "InsertEnter";
      };
    };
    copilot-cmp = {
      enable = true;
    };
  };
}
