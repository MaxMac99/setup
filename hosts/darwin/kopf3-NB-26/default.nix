{
  lib,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  hostSpec = {
    username = "maxvissing";
    hostName = "kopf3-NB-26";
  };

  imports = map lib.custom.relativeToRoot [
    # User profiles
    "modules/profiles/core-user"
    "modules/profiles/development.nix"
    "modules/profiles/fonts.nix"
    "modules/profiles/gcloud.nix"
    "modules/profiles/full-nvim.nix"
    "modules/profiles/darwin-nvim.nix"
    "modules/profiles/work.nix"
    # Applications
    "modules/apps/google-chrome.nix"
    "modules/apps/intellij"
    "modules/apps/rust-rover.nix"
    "modules/apps/ghostty.nix"
    "modules/apps/affinity.nix"
    "modules/apps/tunnelblick.nix"
    "modules/apps/bambu-studio.nix"
    "modules/apps/autodesk-fusion.nix"
    "modules/apps/arc.nix"
    "modules/apps/docker-desktop.nix"
  ];
}