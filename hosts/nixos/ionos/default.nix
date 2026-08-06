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
      "modules/system/overlay-client.nix"
    ])
    ++ [
      ./hardware-configuration.nix
      ./overlay-server.nix
    ];

  hostSpec = {
    username = "max";
    hostName = "ionos";
    isMinimal = true;
  };

  # ionos runs the control server *and* joins as a peer. It advertises no
  # subnet — it has no LAN to offer.
  overlayClient = {
    enable = true;
    authKeySecret = "overlay_authkey";
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

      # Disable reverse path filtering for K3s compatibility.
      #
      # mkForce because the tailscale module sets this to "loose" whenever
      # useRoutingFeatures accepts routes, and an unforced `false` collides
      # with it. Forcing is safe rather than a workaround: `false` disables
      # rp_filter outright, which is strictly more permissive than the "loose"
      # mode tailscale asks for, so overriding cannot break subnet routing —
      # it only keeps the wider allowance k3s's asymmetric flannel paths need.
      checkReversePath = lib.mkForce false;

      # Interface-specific rules - allow Flannel VXLAN only on internal interfaces
      interfaces = {
        wg0.allowedUDPPorts = [8472]; # Flannel VXLAN on WireGuard only
        ens6.allowedUDPPorts = []; # No VXLAN on public interface
      };

      # ⚠️ The 80/443 DNAT to the in-cluster Traefik was removed here in Phase
      # 3, and it was already dead before it was removed.
      #
      # Six rules forwarded ens6:80 and ens6:443 (TCP and QUIC) to
      # networkConfig.legacy.ingressVIP — 192.168.178.10, a MetalLB address
      # Traefik held by first-come luck rather than by configuration. That
      # target stopped responding before Phase 0, so public ingress has been
      # broken for some time and nothing working is being displaced.
      #
      # They have to go rather than merely being unused: DNAT happens in
      # PREROUTING, *before* the local-delivery decision, so while those rules
      # existed Headscale could not have received a packet on 443 no matter
      # what it bound to. Phase 9 rebuilds public ingress on ionos properly
      # with a hostNetwork Traefik (D7), which also ends the masquerading that
      # currently hides every client IP.
      extraCommands = ''
        # Enable IP forwarding
        echo 1 > /proc/sys/net/ipv4/ip_forward
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding

        # Masquerade outgoing traffic so responses route back correctly
        iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
        ip6tables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
      '';

      extraStopCommands = ''
        # Clean up NAT rules on stop
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
    tokenFile = config.sops.secrets.k3s_token.path;
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
    # A **host** key at last (D11/2b.2), completing the correction inherited
    # from Phase 2b item 2. Was /home/max/.ssh/id_ed25519 — a *user* key, and
    # the file the migration notes repeatedly warn must never be renamed while
    # it is the age source, because k3s_token stops decrypting at boot.
    #
    # Safe to flip because it was staged additively: the host-key recipient
    # age19ylfvg7p… has been enrolled in .sops.yaml alongside the user key
    # since 49fa463, both files were re-keyed with their plaintexts unchanged,
    # and ionos was proven to decrypt common.yaml *and* k3s.yaml with this
    # exact key on the box. So this line changes which of two working keys is
    # used, not whether one works — and reverting is one line, not a re-key.
    #
    # ⚠️ Verify after a **reboot**, not after activation. sops-install-secrets
    # runs on both, but only a boot proves the k3s token survives a cold start,
    # which is the failure this ordering exists to prevent.
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.k3s_token = {
      restartUnits = ["k3s.service"];
    };
    templates."k3s-env".content = ''
      K3S_TOKEN=${config.sops.placeholder.k3s_token}
    '';
  };

  # K3s token from sops template
  systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce config.sops.templates."k3s-env".path;

  # ionos rebuilds itself from a clone at /home/max/setup, owned by max, while
  # nixos-rebuild evaluates as root — and nix's libgit2 refuses to open a
  # repository the current user does not own (`error code = 7`). Without this
  # every rebuild fails before it starts.
  #
  # It was set imperatively in /root/.gitconfig on 2026-08-06 to get the 26.11
  # upgrade moving; declaring it here is what stops that undeclared state from
  # being load-bearing. Note the path differs from pi/brink-server, which use
  # an /etc/nixos clone — converging ionos onto that pattern is Phase 13 work.
  #
  # ⚠️ libgit2 reads this from $HOME/.gitconfig, so a rebuild launched under
  # `systemd-run` must be given `--setenv=HOME=/root` or it will not be found.
  programs.git = {
    enable = true;
    config.safe.directory = "/home/max/setup";
  };

  # Fix WireGuard DNS resolution issue during boot
  systemd.services."wireguard-wg0-peer-ulBtv6Iou8HKpJzeJS9YALlZTSKE1+W+fZCEzM3hGiw=" = {
    after = ["nss-lookup.target"];
    wants = ["nss-lookup.target"];
  };

  system.stateVersion = "25.05";
}
