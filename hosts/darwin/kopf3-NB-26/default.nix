{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

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
    jetbrains.idea-ultimate
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
