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
  # ⚠️ **7946 is MetalLB's memberlist, and leaving it out cost an estate-wide
  # outage on 2026-08-13.** The speakers run `hostNetwork` and bind to the node
  # IP, which D3 puts on the overlay — so their gossip crosses this interface
  # and was silently blocked. In L2 mode memberlist is what *elects the
  # announcer*; without it no node claims a VIP, ARP goes unanswered, and every
  # LoadBalancer address stops resolving while the pods behind them stay
  # perfectly healthy.
  #
  # ⚠️ It hid for a day because a formed memberlist keeps working on cached
  # state: the gap only surfaced when `tailscaled` was restarted for an
  # unrelated MTU test, which tore the cluster apart and left it unable to
  # re-form. The symptom pointed at UniFi, then at the rebuild, then at DNS —
  # never at a missing firewall rule. Both protocols are required; memberlist
  # probes over UDP and falls back to TCP, and the log line
  # `"Was able to connect ... over TCP but UDP probes failed"` is the tell.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName} = {
    allowedTCPPorts = [
      6443 # Kubernetes API
      10250 # Kubelet
      2379 # etcd client
      2380 # etcd peer
      7946 # MetalLB memberlist (speaker election)
    ];
    allowedUDPPorts = [
      8472 # Flannel VXLAN
      7946 # MetalLB memberlist (speaker election)
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
