{ pkgs
, ...
}:
{
  programs.nixvim.plugins.treesitter = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.build = ":TSUpdate";
    };
    settings = {
      auto_install = true;
      highlight = {
        enable = true;
      };
      indent = {
        enable = true;
      };
    };
  };
  home.packages = with pkgs; [
    tree-sitter
  ];
}
