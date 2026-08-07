{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable K3S
  services.k3s = {
    enable = true;
    role = "server"; # Will be overridden in individual node configs
    extraFlags = lib.mkDefault (toString [
      "--disable=servicelb" # Use MetalLB instead
      "--write-kubeconfig-mode=644"
      "--tls-san=${config.networking.hostName}"
    ]);
  };

  # Open the k3s ports on the OVERLAY INTERFACE ONLY (7.1).
  #
  # ⚠️ These must never go in the global `allowedTCPPorts`/`allowedUDPPorts`.
  # Those lists apply to *every* interface, which on ionos means the public
  # `ens6` — so until Phase 7 this module accepted the Kubernetes API, the
  # kubelet and **both etcd ports** from the internet at the host firewall.
  #
  # Nothing was ever actually reachable, but only because the **IONOS Cloud
  # firewall** is default-deny: a web-panel control that lives outside this
  # repo and is invisible from inside the VPS. Verified 2026-08-07 — all four
  # ports filtered from off-site while `iptables -S nixos-fw` showed
  # `--dport 6443 -j nixos-fw-accept` with no `-i` restriction. One
  # undocumented, out-of-band control stood between the public internet and
  # etcd, with no second layer behind it.
  #
  # ⚠️ And the per-interface block ionos already had could not have fixed it:
  # `networking.firewall.interfaces.<if>.allowedTCPPorts` is **additive**, so
  # an empty per-interface list subtracts nothing from the global one.
  #
  # Scoping to the overlay is not a compromise — D3 puts every node IP and all
  # flannel traffic on the overlay, so this is the only interface these ports
  # are ever used on. Loopback stays open by default, so a node's own
  # `kubectl` against 127.0.0.1:6443 is unaffected.
  #
  # 2379/2380 are only meaningful on servers, but scoping them to the overlay
  # makes opening them on an agent harmless rather than dangerous.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
    allowedTCPPorts = [
      6443 # Kubernetes API
      10250 # Kubelet
      2379 # etcd client
      2380 # etcd peer
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
    ];
  };

  # Enable container runtime
  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins."io.containerd.grpc.v1.cri" = {
        cni = {
          bin_dir = "/opt/cni/bin";
          conf_dir = "/etc/cni/net.d";
        };
      };
    };
  };

  # Kernel modules for container networking and NFS
  boot.kernelModules = ["br_netfilter" "overlay" "nfs"];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Install Kubernetes tools and NFS client
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
    nfs-utils
  ];

  # Enable NFS client support
  services.rpcbind.enable = true;

  # Limit journal size on disk — logs are shipped to Loki via Alloy
  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';

  # Time synchronization (critical for etcd)
  services.timesyncd.enable = true;

  # Disable swap (Kubernetes requirement)
  swapDevices = [];
}
