{ config, pkgs, lib, ... }:

{
  # Template function to create k3s node configurations
  # Usage: mkK3sNode { nodeName = "k3s-node1"; nodeNumber = 1; isFirstNode = true; }
  mkK3sNode = { nodeName, nodeNumber, isFirstNode ? false }:
    let
      # Generate consistent IDs based on node number
      nodeNumStr = toString nodeNumber;
      paddedNum = lib.strings.padLeft 2 "0" nodeNumStr;
      hostId = "${paddedNum}${paddedNum}${paddedNum}${paddedNum}";
      macAddress = "02:00:00:01:01:${paddedNum}";
    in
    {
      microvm.vms.${nodeName} = {
        # Use cloud-hypervisor for better performance
        hypervisor = "cloud-hypervisor";

        # Resource allocation
        vcpu = 2;
        mem = 6144; # 6GB

        # Networking - TAP device bridged to host network
        interfaces = [{
          type = "tap";
          id = "vm-${nodeName}";
          mac = macAddress;
        }];

        # Share the nix store from host (reduces disk usage and speeds up builds)
        shares = [{
          proto = "virtiofs";
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
        }];

        # MicroVM configuration
        config = {
          imports = lib.flatten [
            (map lib.custom.relativeToRoot [
              "hosts/common/core"
              "hosts/common/optional/nixos/openssh.nix"
              "modules/nixos/k3s-base.nix"
            ])
          ];

          # Host specification
          hostSpec = {
            username = "max";
            hostName = nodeName;
            isDarwin = false;
            isWork = false;
            isServer = true;
            isMinimal = true;
          };

          # Networking
          networking = {
            hostName = nodeName;
            hostId = hostId;
            useDHCP = false;
            firewall.enable = false;
            nameservers = config.networkConfig.dns.servers;
            interfaces.eth0 = {
              ipv4.addresses = [{
                address = config.networkConfig.staticIPs.${nodeName};
                prefixLength = 24;
              }];
            };
            defaultGateway = config.networkConfig.gateway;
          };

          # K3s configuration - first node initializes, others join
          services.k3s.extraFlags = toString (
            [ "--node-name=${nodeName}" ] ++
            (if isFirstNode then
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
      };
    };
}