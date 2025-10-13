{lib, ...}: {
  nixpkgs.hostPlatform = "aarch64-darwin";

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
    ])
  ];

  homebrew.casks = [
    "tunnelblick"
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
