{ ... }:
{
  imports = [
    common/core

    common/optional/browsers/chrome.nix

    # common/optional/terminals/alacritty.nix
    common/optional/terminals/ghostty.nix
    common/optional/ides/clion.nix
    common/optional/ides/intellij.nix
    common/optional/ides/rust-rover.nix
    common/optional/discord.nix
  ];
}
