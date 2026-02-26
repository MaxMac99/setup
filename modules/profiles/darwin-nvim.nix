# macOS neovim profile - LaTeX, Xcode/Swift support
{config, ...}: {
  home-manager.users.${config.hostSpec.username}.imports = [
    ./core-user/nvf/latex.nix
    ./core-user/nvf/xcode
  ];
}