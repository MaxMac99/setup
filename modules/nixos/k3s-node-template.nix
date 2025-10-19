{ lib, ... }:

{
  # Simple template function that returns a k3s node configuration
  # Usage: mkK3sNode { nodeName = "k3s-node1"; nodeNumber = 1; isFirstNode = true; }
  mkK3sNode = { nodeName, nodeNumber, isFirstNode ? false }:
    let
      paddedNum = lib.strings.padLeft 2 "0" (toString nodeNumber);
    in
    { config, pkgs, inputs, ... }: {
      imports = [
        inputs.microvm.nixosModules.microvm
        (lib.custom.relativeToRoot "hosts/common/core")
        (lib.custom.relativeToRoot "hosts/common/optional/nixos/openssh.nix")
        (lib.custom.relativeToRoot "modules/nixos/k3s-base.nix")
      ];

      nixpkgs.hostPlatform = "x86_64-linux";

      hostSpec = {
        username = "max";
        hostName = nodeName;
        isDarwin = false;
        isWork = false;
        isServer = true;
        isMinimal = true;
      };

      microvm = {
        hypervisor = "cloud-hypervisor";
        vcpu = 2;
        mem = 6144;

        interfaces = [{
          type = "tap";
          id = "vm-${nodeName}";
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
        hostName = nodeName;
        hostId = "${paddedNum}${paddedNum}${paddedNum}${paddedNum}";
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

      services.k3s.extraFlags = toString (
        [ "--node-name=${nodeName}" ] ++
        (if isFirstNode then
          [ "--cluster-init" ]
        else
          [ "--server=https://${config.networkConfig.staticIPs.k3s-node1}:6443" ])
      );

      systemd.services.k3s.serviceConfig.EnvironmentFile =
        pkgs.writeText "k3s-env" ''
          K3S_TOKEN=REPLACE_WITH_YOUR_TOKEN
        '';

      system.stateVersion = "24.11";
    };
}