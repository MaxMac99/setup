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

      # Enable writable nix store overlay
      writableStoreOverlay = "/nix/.rw-store";

      # Create a writable volume for /nix/var and other state
      volumes = [{
        image = "nix-state.img";
        mountPoint = "/nix/var";
        size = 2048; # 2GB for nix state
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

    # K3s token - for now use a placeholder
    # TODO: Replace with actual secret management
    systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce (
      pkgs.writeText "k3s-env" ''
        K3S_TOKEN=7KQZfcTkcTPj4iCoSdRcm6qS7LdUm/MVF5fHcpkUjzUREPLACE_WITH_YOUR_ACTUAL_TOKEN
      ''
    );

    # Disable nix store optimization (incompatible with writableStoreOverlay)
    nix = {
      optimise.automatic = lib.mkForce false;
      settings.auto-optimise-store = lib.mkForce false;
    };

    system.stateVersion = "24.11";
  };
}