{ pkgs
, ...
}:
{
  programs.nixvim.plugins.lint = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.event = [ "BufReadPre" "BufNewFile" ];
    };
    lintersByFt = {
      nix = [ "statix" ];
      lua = [ "selene" ];
      javascript = [ "eslint_d" ];
      typescript = [ "eslint_d" ];
      json = [ "jsonlint" ];
      markdown = [ "markdownlint" ];
      swift = [ "swiftlint" ];
    };
    luaConfig.post = ''
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
          group = lint_augroup,
          callback = function()
              __lint.try_lint()
          end,
      })
    '';
  };
  home.packages = with pkgs; [
    swiftlint
  ];
}
