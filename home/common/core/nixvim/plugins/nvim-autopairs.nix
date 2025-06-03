{
  programs.nixvim.plugins.nvim-autopairs = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.event = "InsertEnter";
    };
    luaConfig.post = ''
      local cmp_autopairs = require 'nvim-autopairs.completion.cmp'
      local cmp = require 'cmp'
      cmp.event:on('confirm_done', cmp_autopairs.on_confirm_done())
    '';
  };
}
