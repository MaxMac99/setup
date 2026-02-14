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
    "bambu-studio"
    "autodesk-fusion"
    "vlc"
  ];

  environment.systemPackages = with pkgs; [
    google-chrome
    discord
    jetbrains.idea
    jetbrains.rust-rover
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
