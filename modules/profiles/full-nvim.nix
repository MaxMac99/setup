# Advanced neovim profile - AI, LSP, debugger, formatter, etc.
{config, ...}: {
  home-manager.users.${config.hostSpec.username}.imports = [
    ./core-user/nvf/ai.nix
    ./core-user/nvf/debugger.nix
    ./core-user/nvf/formatter.nix
    ./core-user/nvf/languages.nix
    ./core-user/nvf/lsp.nix
    ./core-user/nvf/ui.nix
    ./core-user/nvf/utility.nix
    ./core-user/nvf/visuals.nix
  ];
}