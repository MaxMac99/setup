{lib, ...}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
    ])
  ];

  homebrew.casks = [
    "affinity-designer"
    "affinity-photo"
    "bambu-studio"
    "autodesk-fusion"
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
