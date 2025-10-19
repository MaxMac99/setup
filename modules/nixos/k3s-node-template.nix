{ config, pkgs, lib, modulesPath, ... }:

{
  # Shared k3s node configuration template
  # This module provides common configuration for all k3s microvm nodes

  options.k3sNode = {
    nodeName = lib.mkOption {
      type = lib.types.str;
      description = "Name of the k3s node";
    };

    nodeNumber = lib.mkOption {
      type = lib.types.int;
      description = "Node number (1, 2, 3, etc.)";
    };

    isFirstNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this is the first node (cluster init)";
    };
  };

  config = let
    cfg = config.k3sNode;
    nodeNumStr = toString cfg.nodeNumber;
    paddedNum = lib.strings.padLeft 2 "0" nodeNumStr;
    hostId = "${paddedNum}${paddedNum}${paddedNum}${paddedNum}";
  in {
    imports = lib.flatten [
      (map lib.custom.relativeToRoot [
        "hosts/common/core"
        "hosts/common/optional/nixos/openssh.nix"
        "modules/nixos/k3s-base.nix"
        "modules/common/network-config.nix"
      ])
    ];

    # MicroVM configuration - these are the VM hardware settings
    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 2;
      mem = 6144; # 6GB

      interfaces = [{
        type = "tap";
        id = "vm-${cfg.nodeName}";
        mac = "02:00:00:01:01:${paddedNum}";
      }];

      shares = [{
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }];
    };

    # System platform
    nixpkgs.hostPlatform = "x86_64-linux";

    # Host specification
    hostSpec = {
      username = "max";
      hostName = cfg.nodeName;
      isDarwin = false;
      isWork = false;
      isServer = true;
      isMinimal = true;
    };

    # Networking
    networking = {
      hostName = cfg.nodeName;
      hostId = hostId;
      useDHCP = false;
      firewall.enable = false;
      nameservers = config.networkConfig.dns.servers;
      interfaces.eth0 = {
        ipv4.addresses = [{
          address = config.networkConfig.staticIPs.${cfg.nodeName};
          prefixLength = 24;
        }];
      };
      defaultGateway = config.networkConfig.gateway;
    };

    # K3s configuration - first node initializes, others join
    services.k3s.extraFlags = toString (
      [ "--node-name=${cfg.nodeName}" ] ++
      (if cfg.isFirstNode then
        [ "--cluster-init" ]
      else
        [ "--server=https://${config.networkConfig.staticIPs.k3s-node1}:6443" ])
    );

    # K3s token and server address via environment file
    systemd.services.k3s.serviceConfig.EnvironmentFile =
      pkgs.writeText "k3s-env" ''
        K3S_TOKEN=REPLACE_WITH_YOUR_TOKEN
      '';

    system.stateVersion = "24.11";
  };
}