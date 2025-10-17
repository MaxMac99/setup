{lib, ...}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/common/optional/nixos/openssh.nix"
      "hosts/common/optional/nixos/ipforward.nix"
    ])
    ./hardware-configuration.nix
  ];

  hostSpec = {
    username = "max";
    hostName = "ionos";
    isDarwin = false;
    isWork = false;
    isServer = true;
    isMinimal = true;
  };

  zramSwap.enable = true;

  networking = {
    domain = "";
    firewall = {
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [56527];
    };
    wireguard.interfaces = {
      wg0 = {
        ips = ["192.168.178.201/24" "fda8:a1db:5685::201/64"];
        listenPort = 56527;
        privateKeyFile = "/home/max/.wireguard/private_key";

        peers = [
          {
            publicKey = "ulBtv6Iou8HKpJzeJS9YALlZTSKE1+W+fZCEzM3hGiw=";
            presharedKeyFile = "/home/max/.wireguard/preshared_key";
            allowedIPs = ["192.168.178.0/24" "fda8:a1db:5685::/64"];
            endpoint = "bzwkhrd8hexv5q4g.myfritz.net:56527";
            persistentKeepalive = 25;
          }
        ];
      };
    };
  };

  system.stateVersion = "25.05";
}
