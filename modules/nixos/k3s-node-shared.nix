{ config, pkgs, lib, inputs, ... }:

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

      shares = [{
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
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
      matchConfig.Type = "ether";
      networkConfig = {
        Address = "${config.networkConfig.staticIPs.${cfg.nodeName}}/24";
        Gateway = config.networkConfig.gateway;
        DNS = config.networkConfig.dns.servers;
        DHCP = "no";
      };
      linkConfig.RequiredForOnline = "routable";
    };

    services.k3s.extraFlags = lib.mkForce (toString (
      [
        "--disable=traefik"
        "--disable=servicelb"
        "--write-kubeconfig-mode=644"
        "--tls-san=${cfg.nodeName}"
        "--node-name=${cfg.nodeName}"
      ] ++
      (if cfg.isFirstNode then
        [ "--cluster-init" ]
      else
        [ "--server=https://${config.networkConfig.staticIPs.k3s-node1}:6443" ])
    ));

    # Configure sops secret for k3s token
    sops.secrets.k3s_token = {
      sopsFile = lib.custom.relativeToRoot "secrets/k3s.yaml";
      restartUnits = [ "k3s.service" ];
    };

    # Use the sops secret as environment file
    systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce [
      (pkgs.writeText "k3s-env-base" ''
        # Additional K3S environment variables can go here
      '')
      config.sops.secrets.k3s_token.path
    ];

    system.stateVersion = "24.11";
  };
}