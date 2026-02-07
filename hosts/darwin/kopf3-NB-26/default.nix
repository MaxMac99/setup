{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Override nushell to disable tests (they fail in macOS sandbox)
  nixpkgs.overlays = [
    (final: prev: {
      nushell = prev.nushell.overrideAttrs (oldAttrs: {
        doCheck = false;
      });
    })
  ];

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
    ])
  ];

  homebrew.casks = [
    "affinity"
    "tunnelblick"
    "bambu-studio"
    "autodesk-fusion"
  ];

  environment.systemPackages = with pkgs; [
    google-chrome
    jetbrains.idea
    jetbrains.rust-rover
  ];

  hostSpec = {
    username = "maxvissing";
    hostName = "kopf3-NB-26";
    isDarwin = true;
    isWork = true;
    isServer = false;
    isMinimal = false;
  };
}
