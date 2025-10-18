{ config, lib, pkgs, ... }:

{
  # Enable K3S
  services.k3s = {
    enable = true;
    role = "server"; # Will be overridden in individual node configs
    extraFlags = toString [
      "--disable=traefik"  # We'll use a different ingress controller
      "--disable=servicelb"  # Use MetalLB instead
      "--write-kubeconfig-mode=644"
      "--tls-san=${config.networking.hostName}"
    ];
  };

  # Open firewall for K3S
  networking.firewall = {
    allowedTCPPorts = [
      6443  # Kubernetes API
      10250 # Kubelet
      2379  # etcd client
      2380  # etcd peer
    ];
    allowedUDPPorts = [
      8472  # Flannel VXLAN
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

  # Kernel modules for container networking
  boot.kernelModules = [ "br_netfilter" "overlay" ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # Install Kubernetes tools
  environment.systemPackages = with pkgs; [
    kubectl
    kubernetes-helm
    k9s
  ];

  # Time synchronization (critical for etcd)
  services.timesyncd.enable = true;

  # Disable swap (Kubernetes requirement)
  swapDevices = [ ];
}
