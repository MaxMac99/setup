{lib, pkgs, config, ...}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/common/optional/nixos/openssh.nix"
      "modules/nixos/k3s-base.nix"
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

  # Disable swap completely to avoid kswapd0 CPU issues
  zramSwap.enable = false;
  swapDevices = [ ];

  networking = {
    domain = "";

    # Enable IPv6
    enableIPv6 = true;

    # Configure ens6 interface for public access
    interfaces.ens6 = {
      useDHCP = true;  # Get IPv4 via DHCP
      ipv6 = {
        addresses = [];  # Let SLAAC handle IPv6 addresses
        routes = [];
      };
    };

    firewall = {
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [56527];  # WireGuard only

      # Trust interfaces used by K3s
      trustedInterfaces = [ "flannel.1" "cni0" "flannel-v6.1" "wg0" ];

      # Disable reverse path filtering for K3s compatibility
      checkReversePath = false;

      # Interface-specific rules - allow Flannel VXLAN only on internal interfaces
      interfaces = {
        wg0.allowedUDPPorts = [ 8472 ];  # Flannel VXLAN on WireGuard only
        ens6.allowedUDPPorts = [ ];      # No VXLAN on public interface
      };
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
            endpoint = "xswl3ocz7lm59gcs.myfritz.net:56527";
            persistentKeepalive = 25;
          }
        ];
      };
    };
  };

  # Configure K3s as agent (worker node)
  services.k3s = {
    role = lib.mkForce "agent";
    serverAddr = "https://192.168.178.5:6443";  # k3s-node1
    extraFlags = lib.mkForce (toString [
      "--node-name=ionos"
      "--node-label=edge=true"  # Mark as edge node (custom label)
      "--node-label=topology.kubernetes.io/zone=external"  # For scheduling
      "--node-ip=192.168.178.201,fda8:a1db:5685::201"
      "--flannel-iface=wg0"  # Use WireGuard interface for Flannel VXLAN traffic
      # Taint to prevent accidental scheduling - only pods with toleration will run here
      "--node-taint=edge=true:NoSchedule"
    ]);
  };

  # Configure sops secret for K3s token
  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
    age.sshKeyPaths = [ "/home/max/.ssh/id_ed25519" ];  # Use user SSH key for age
    secrets.k3s_token = {
      restartUnits = [ "k3s.service" ];
    };
    templates."k3s-env".content = ''
      K3S_TOKEN=${config.sops.placeholder.k3s_token}
    '';
  };

  # K3s token from sops template
  systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce config.sops.templates."k3s-env".path;

  # Fix WireGuard DNS resolution issue during boot
  # Ensure WireGuard peer waits for DNS to be available
  systemd.services."wireguard-wg0-peer-ulBtv6Iou8HKpJzeJS9YALlZTSKE1+W+fZCEzM3hGiw=" = {
    after = [ "nss-lookup.target" ];
    wants = [ "nss-lookup.target" ];
  };

  system.stateVersion = "25.05";
}
