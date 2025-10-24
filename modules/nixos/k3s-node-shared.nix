{ config, pkgs, lib, inputs, options, ... }:

let
  cfg = config.k3sNode;
  paddedNum = lib.fixedWidthString 2 "0" (toString cfg.nodeNumber);
in
{
  imports = [
    inputs.microvm.nixosModules.microvm
    (lib.custom.relativeToRoot "hosts/common/core")
    (lib.custom.relativeToRoot "hosts/common/optional/nixos/openssh.nix")
    (lib.custom.relativeToRoot "modules/nixos/k3s-base.nix")
    (lib.custom.relativeToRoot "modules/nixos/minimal-zsh.nix")
  ];

  options.k3sNode = {
    nodeName = lib.mkOption {
      type = lib.types.str;
    };
    nodeNumber = lib.mkOption {
      type = lib.types.int;
    };
    isFirstNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  config = {
    nixpkgs.hostPlatform = "x86_64-linux";

    hostSpec = {
      username = "max";
      hostName = cfg.nodeName;
      isDarwin = false;
      isWork = false;
      isServer = true;
      isMinimal = true;
    };

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 2;
      mem = 6144;

      # vsock for systemd-notify support
      vsock.cid = 100 + cfg.nodeNumber;

      interfaces = [{
        type = "tap";
        id = "vm-${cfg.nodeName}";
        mac = "02:00:00:01:01:${paddedNum}";
      }];

      shares = [
        {
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }
        {
          proto = "virtiofs";
          tag = "k8s-fast";
          source = "/fast/k8s";
          mountPoint = "/mnt/k8s-fast";
        }
      ];

      # Enable writable nix store overlay
      writableStoreOverlay = "/nix/.rw-store";

      # Create a writable volume for persistent state
      volumes = [{
        image = "var-state.img";
        mountPoint = "/var";
        size = 4096; # 4GB for state
      }];
    };

    networking = {
      hostName = cfg.nodeName;
      hostId = "${paddedNum}${paddedNum}${paddedNum}${paddedNum}";
      useDHCP = false;
      useNetworkd = true;
      firewall.enable = false;
    };

    # systemd-networkd configuration for the guest
    systemd.network.enable = true;
    systemd.network.networks."20-wired" = {
      matchConfig.Name = "en*";  # Match en* interfaces (ens*, enp*, etc)
      networkConfig = {
        DHCP = "no";
        DNS = config.networkConfig.dns.servers;
        IPv6AcceptRA = false;
      };
      address = [
        "${config.networkConfig.staticIPs.${cfg.nodeName}}/24"
        "${config.networkConfig.staticIPv6s.${cfg.nodeName}}/64"
      ];
      routes = [
        { routeConfig.Gateway = config.networkConfig.gateway; }
      ];
      linkConfig.RequiredForOnline = "routable";
    };

    services.k3s.extraFlags = lib.mkForce (toString (
      [
        "--disable=servicelb"  # Use MetalLB for LoadBalancer services
        "--write-kubeconfig-mode=644"
        "--tls-san=${cfg.nodeName}"
        "--tls-san=${config.networkConfig.staticIPv6s.${cfg.nodeName}}"
        "--node-name=${cfg.nodeName}"
        # Dual-stack configuration
        "--node-ip=${config.networkConfig.staticIPs.${cfg.nodeName}},${config.networkConfig.staticIPv6s.${cfg.nodeName}}"
        "--cluster-cidr=10.42.0.0/16,fd01::/48"   # Pod IPv4 and IPv6 ranges
        "--service-cidr=10.43.0.0/16,fd02::/112"  # Service IPv4 and IPv6 ranges
      ] ++
      (if cfg.isFirstNode then
        [ "--cluster-init" ]
      else
        [ "--server=https://${config.networkConfig.staticIPs.k3s-node1}:6443" ])
    ));

    # Configure sops secret for K3s token
    sops = {
      defaultSopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
      secrets.k3s_token = {
        restartUnits = [ "k3s.service" ];
      };
      templates."k3s-env".content = ''
        K3S_TOKEN=${config.sops.placeholder.k3s_token}
      '';
    };

    # K3s token from sops template
    systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce config.sops.templates."k3s-env".path;

    # Disable nix store optimization (incompatible with writableStoreOverlay)
    nix = {
      optimise.automatic = lib.mkForce false;
      settings.auto-optimise-store = lib.mkForce false;
    };

    # Ensure SSH host keys are persistent
    services.openssh.hostKeys = [
      {
        path = "/var/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/var/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];

    system.stateVersion = "24.11";
  };
}