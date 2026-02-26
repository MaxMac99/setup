{ config, pkgs, lib, inputs, options, ... }:

let
  cfg = config.k3sNode;
  paddedNum = lib.fixedWidthString 2 "0" (toString cfg.nodeNumber);
in
{
  imports = [
    inputs.microvm.nixosModules.microvm
    (lib.custom.relativeToRoot "modules/system/openssh.nix")
    (lib.custom.relativeToRoot "modules/system/k3s-base.nix")
    (lib.custom.relativeToRoot "modules/system/minimal-zsh.nix")
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
        size = 51200; # 50GB for state
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
        { Gateway = config.networkConfig.gateway; }
      ];
      linkConfig.RequiredForOnline = "routable";
    };

    services.k3s.extraFlags = lib.mkForce (toString (
      [
        "--disable=servicelb"  # Use MetalLB for LoadBalancer services
        "--disable=traefik"    # Use Pulumi-managed Traefik instead
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
      age.sshKeyPaths = [ "/var/ssh/ssh_host_ed25519_key" ];  # Use VM's persistent host key
      secrets.k3s_token = {
        restartUnits = [ "k3s.service" ];
      };
      templates."k3s-env".content = ''
        K3S_TOKEN=${config.sops.placeholder.k3s_token}
      '';
    };

    # K3s token from sops template
    systemd.services.k3s.serviceConfig.EnvironmentFile = lib.mkForce config.sops.templates."k3s-env".path;

    # Configure local-path provisioner to use fast ZFS pool (first node only)
    systemd.tmpfiles.rules = lib.mkIf cfg.isFirstNode (
      let
        localPathConfigMap = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            name = "local-path-config";
            namespace = "kube-system";
          };
          data = {
            "config.json" = builtins.toJSON {
              nodePathMap = [{
                node = "DEFAULT_PATH_FOR_NON_LISTED_NODES";
                paths = [ "/mnt/k8s-fast" ];
              }];
            };
            setup = ''
              #!/bin/sh
              set -eu
              mkdir -m 0777 -p "$VOL_DIR"
              chmod 700 "$VOL_DIR/.."
            '';
            teardown = ''
              #!/bin/sh
              set -eu
              rm -rf "$VOL_DIR"
            '';
            "helperPod.yaml" = lib.generators.toYAML {} {
              apiVersion = "v1";
              kind = "Pod";
              metadata = {
                name = "helper-pod";
              };
              spec = {
                containers = [{
                  name = "helper-pod";
                  image = "rancher/mirrored-library-busybox:1.36.1";
                  imagePullPolicy = "IfNotPresent";
                }];
              };
            };
          };
        };
        configMapYaml = lib.generators.toYAML {} localPathConfigMap;
      in [
        "d /var/lib/rancher/k3s/server/manifests 0755 root root -"
        "f /var/lib/rancher/k3s/server/manifests/local-path-config.yaml 0644 root root - ${pkgs.writeText "local-path-config.yaml" configMapYaml}"
      ]
    );

    systemd.services.local-path-config = lib.mkIf cfg.isFirstNode {
        description = "Configure local-path-provisioner to use ZFS pool";
        after = [ "k3s.service" ];
        requires = [ "k3s.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.kubectl ];
        environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
        script = ''
          until kubectl get configmap -n kube-system local-path-config 2>/dev/null; do sleep 5; done
          kubectl patch configmap -n kube-system local-path-config --type merge \
            -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/mnt/k8s-fast/local-path-provisioner\"]}]}"}}'
        '';
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

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
    ];

    system.stateVersion = "24.11";
  };
}