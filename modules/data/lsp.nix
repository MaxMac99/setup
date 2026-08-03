# Language servers - one list, shared by every editor and agent
{
  pkgs,
  lib,
  ...
}: {
  options.lspPackages = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    description = ''
      Language servers put on PATH for neovim, opencode, Zed and friends.

      nvf resolves its servers from the same nixpkgs, so keeping the server
      choice aligned here is enough to guarantee identical binaries.
    '';
    default = with pkgs; [
      nixd
      rust-analyzer
      gopls
      typescript-language-server
      pyright
      lua-language-server
      bash-language-server
      yaml-language-server
      texlab
    ];
  };
}
