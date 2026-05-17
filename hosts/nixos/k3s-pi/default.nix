{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/system/k3s-base.nix"
      "modules/system/minimal-zsh.nix"
    ])
    ++ (with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-4.base
      trusted-nix-caches
      inputs.nixos-raspberrypi.lib.inject-overlays
    ])
    ++ [./hardware-configuration.nix];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Pi PoE+ HAT: enable the rpi-poe-plus DT overlay so the EMC2301 fan
  # controller and temperature-based fan curve work.
  hardware.raspberry-pi.config.all.dt-overlays.rpi-poe-plus = {
    enable = true;
    params = {};
  };

  hostSpec = {
    username = "max";
    hostName = "k3s-pi";
    isMinimal = true;
  };

  networking = {
    hostName = "k3s-pi";
    hostId = "03030303";
    useDHCP = false;
    useNetworkd = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
      allowedUDPPorts = [67]; # DHCP server
    };
  };

  systemd.network.enable = true;
  systemd.network.networks."20-wired" = {
    matchConfig.Name = "end0";
    networkConfig = {
      DHCP = "no";
      DNS = config.networkConfig.dns.servers;
      IPv6AcceptRA = false;
    };
    address = [
      "${config.networkConfig.staticIPs.k3s-pi}/24"
      "${config.networkConfig.staticIPv6s.k3s-pi}/64"
    ];
    routes = [
      {Gateway = config.networkConfig.gateway;}
    ];
    linkConfig.RequiredForOnline = "routable";
  };

  services.k3s = {
    role = lib.mkForce "agent";
    tokenFile = config.sops.secrets.k3s_token.path;
    serverAddr = "https://${config.networkConfig.staticIPs.k3s-node1}:6443";
    extraFlags = lib.mkForce (toString [
      "--node-name=k3s-pi"
      "--node-label=topology.kubernetes.io/zone=home"
      "--node-ip=${config.networkConfig.staticIPs.k3s-pi},${config.networkConfig.staticIPv6s.k3s-pi}"
    ]);
  };

  # Kea DHCPv4 — replaces FritzBox DHCP.
  # After AdGuard is deployed in k3s with a MetalLB IP, change
  # domain-name-servers below to that IP.
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = ["end0"];
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      valid-lifetime = 4000;
      renew-timer = 1000;
      rebind-timer = 2000;
      subnet4 = [
        {
          id = 1;
          subnet = "192.168.178.0/24";
          pools = [{pool = "192.168.178.50 - 192.168.178.200";}];
          option-data = [
            {
              name = "routers";
              data = config.networkConfig.gateway;
            }
            {
              name = "domain-name-servers";
              data = config.networkConfig.gateway;
            }
            {
              name = "domain-name";
              data = config.networkConfig.domain;
            }
          ];
        }
      ];
    };
  };

  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.k3s_token = {
      restartUnits = ["k3s.service"];
    };
  };

  system.stateVersion = "25.11";
}
