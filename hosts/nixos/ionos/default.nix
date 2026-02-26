{
  lib,
  config,
  ...
}: {
  nixpkgs.hostPlatform = "x86_64-linux";

  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/system/k3s-base.nix"
      "modules/system/minimal-zsh.nix"
    ])
    ++ [./hardware-configuration.nix];

  hostSpec = {
    username = "max";
    hostName = "ionos";
    isMinimal = true;
  };

  # Disable swap completely to avoid kswapd0 CPU issues
  zramSwap.enable = false;
  swapDevices = [];

  networking = {
    domain = "";

    # Enable IPv6
    enableIPv6 = true;

    # Configure ens6 interface for public access
    interfaces.ens6 = {
      useDHCP = true; # Get IPv4 via DHCP
      ipv6 = {
        addresses = []; # Let SLAAC handle IPv6 addresses
        routes = [];
      };
    };

    firewall = {
      allowedTCPPorts = [22 80 443];
      allowedUDPPorts = [56527 443]; # WireGuard + QUIC/HTTP3

      # Trust interfaces used by K3s
      trustedInterfaces = ["flannel.1" "cni0" "flannel-v6.1" "wg0"];

      # Disable reverse path filtering for K3s compatibility
      checkReversePath = false;

      # Interface-specific rules - allow Flannel VXLAN only on internal interfaces
      interfaces = {
        wg0.allowedUDPPorts = [8472]; # Flannel VXLAN on WireGuard only
        ens6.allowedUDPPorts = []; # No VXLAN on public interface
      };

      # Enable NAT for forwarding traffic to internal Traefik
      extraCommands = ''
        # Enable IP forwarding
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

        # Forward HTTP (80) traffic from public interface to internal Traefik
        iptables -t nat -A PREROUTING -i ens6 -p tcp --dport 80 -j DNAT --to-destination 192.168.178.10:80
        ip6tables -t nat -A PREROUTING -i ens6 -p tcp --dport 80 -j DNAT --to-destination [fda8:a1db:5685::10]:80

        # Forward HTTPS (443) TCP traffic from public interface to internal Traefik
        iptables -t nat -A PREROUTING -i ens6 -p tcp --dport 443 -j DNAT --to-destination 192.168.178.10:443
        ip6tables -t nat -A PREROUTING -i ens6 -p tcp --dport 443 -j DNAT --to-destination [fda8:a1db:5685::10]:443

        # Forward HTTPS (443) UDP traffic for HTTP/3 QUIC
        iptables -t nat -A PREROUTING -i ens6 -p udp --dport 443 -j DNAT --to-destination 192.168.178.10:443
        ip6tables -t nat -A PREROUTING -i ens6 -p udp --dport 443 -j DNAT --to-destination [fda8:a1db:5685::10]:443

        # Masquerade outgoing traffic so responses route back correctly
        iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
        ip6tables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
      '';

      extraStopCommands = ''
        # Clean up NAT rules on stop
        iptables -t nat -D PREROUTING -i ens6 -p tcp --dport 80 -j DNAT --to-destination 192.168.178.10:80 2>/dev/null || true
        ip6tables -t nat -D PREROUTING -i ens6 -p tcp --dport 80 -j DNAT --to-destination [fda8:a1db:5685::10]:80 2>/dev/null || true
        iptables -t nat -D PREROUTING -i ens6 -p tcp --dport 443 -j DNAT --to-destination 192.168.178.10:443 2>/dev/null || true
        ip6tables -t nat -D PREROUTING -i ens6 -p tcp --dport 443 -j DNAT --to-destination [fda8:a1db:5685::10]:443 2>/dev/null || true
        iptables -t nat -D PREROUTING -i ens6 -p udp --dport 443 -j DNAT --to-destination 192.168.178.10:443 2>/dev/null || true
        ip6tables -t nat -D PREROUTING -i ens6 -p udp --dport 443 -j DNAT --to-destination [fda8:a1db:5685::10]:443 2>/dev/null || true
        iptables -t nat -D POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || true
        ip6tables -t nat -D POSTROUTING -o wg0 -j MASQUERADE 2>/dev/null || true
      '';
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
    serverAddr = "https://192.168.178.5:6443"; # k3s-node1
    extraFlags = lib.mkForce (toString [
      "--node-name=ionos"
      "--node-label=edge=true" # Mark as edge node (custom label)
      "--node-label=topology.kubernetes.io/zone=external" # For scheduling
      "--node-ip=192.168.178.201,fda8:a1db:5685::201"
      "--flannel-iface=wg0" # Use WireGuard interface for Flannel VXLAN traffic
      # Taint to prevent accidental scheduling - only pods with toleration will run here
      "--node-taint=edge=true:NoSchedule"
    ]);
  };

  # Configure sops secret for K3s token
  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
    age.sshKeyPaths = ["/home/max/.ssh/id_ed25519"]; # Use user SSH key for age
    secrets.k3s_token = {
      restartUnits = ["k3s.service"];
    };
    templates."k3s-env".content = ''
      K3S_TOKEN=${config.sops.placeholder.k3s_token}
    '';
  };

  # K3s token from sops template
  systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce config.sops.templates."k3s-env".path;

  # Fix WireGuard DNS resolution issue during boot
  systemd.services."wireguard-wg0-peer-ulBtv6Iou8HKpJzeJS9YALlZTSKE1+W+fZCEzM3hGiw=" = {
    after = ["nss-lookup.target"];
    wants = ["nss-lookup.target"];
  };

  system.stateVersion = "25.05";
}