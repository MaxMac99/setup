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
    "bambu-studio"
    "autodesk-fusion"
    "vlc"
  ];

  environment.systemPackages = with pkgs; [
    google-chrome
    discord
    jetbrains.idea
    jetbrains.rust-rover
    renovate
    zed-editor
  ];

  hostSpec = {
    username = "maxvissing";
    hostName = "Maxs-MacBook-Pro";
    isDarwin = true;
    isWork = false;
    isServer = false;
    isMinimal = false;
  };
}
