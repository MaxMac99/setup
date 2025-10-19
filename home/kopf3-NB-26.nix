{...}: {
  imports = [
    common/optional/browsers/chrome.nix

    common/optional/terminals/ghostty.nix
    common/optional/ides/intellij.nix
    common/optional/ides/rust-rover.nix
  ];
}
