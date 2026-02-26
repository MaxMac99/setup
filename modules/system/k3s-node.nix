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
        "--disable=local-storage"
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
          localPathManifest = pkgs.writeText "local-path-provisioner.yaml" ''
            apiVersion: v1
            kind: ServiceAccount
            metadata:
              name: local-path-provisioner-service-account
              namespace: kube-system
            ---
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRole
            metadata:
              name: local-path-provisioner-role
            rules:
              - apiGroups: [""]
                resources: ["nodes", "persistentvolumeclaims", "configmaps", "pods", "pods/log"]
                verbs: ["get", "list", "watch"]
              - apiGroups: [""]
                resources: ["pods"]
                verbs: ["create", "delete"]
              - apiGroups: [""]
                resources: ["persistentvolumes"]
                verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
              - apiGroups: [""]
                resources: ["events"]
                verbs: ["create", "patch"]
              - apiGroups: ["storage.k8s.io"]
                resources: ["storageclasses"]
                verbs: ["get", "list", "watch"]
            ---
            apiVersion: rbac.authorization.k8s.io/v1
            kind: ClusterRoleBinding
            metadata:
              name: local-path-provisioner-bind
            roleRef:
              apiGroup: rbac.authorization.k8s.io
              kind: ClusterRole
              name: local-path-provisioner-role
            subjects:
              - kind: ServiceAccount
                name: local-path-provisioner-service-account
                namespace: kube-system
            ---
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: local-path-provisioner
              namespace: kube-system
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: local-path-provisioner
              template:
                metadata:
                  labels:
                    app: local-path-provisioner
                spec:
                  serviceAccountName: local-path-provisioner-service-account
                  containers:
                    - name: local-path-provisioner
                      image: rancher/local-path-provisioner:v0.0.30
                      command:
                        - local-path-provisioner
                        - --debug
                        - start
                        - --config
                        - /etc/config/config.json
                        - --service-account-name
                        - local-path-provisioner-service-account
                      volumeMounts:
                        - name: config-volume
                          mountPath: /etc/config/
                      env:
                        - name: POD_NAMESPACE
                          valueFrom:
                            fieldRef:
                              fieldPath: metadata.namespace
                  volumes:
                    - name: config-volume
                      configMap:
                        name: local-path-config
            ---
            apiVersion: storage.k8s.io/v1
            kind: StorageClass
            metadata:
              name: local-path
              annotations:
                storageclass.kubernetes.io/is-default-class: "true"
            provisioner: rancher.io/local-path
            volumeBindingMode: WaitForFirstConsumer
            reclaimPolicy: Delete
            ---
            apiVersion: v1
            kind: ConfigMap
            metadata:
              name: local-path-config
              namespace: kube-system
            data:
              config.json: |-
                {
                  "nodePathMap": [
                    {
                      "node": "DEFAULT_PATH_FOR_NON_LISTED_NODES",
                      "paths": ["/mnt/k8s-fast/local-path-provisioner"]
                    }
                  ]
                }
              setup: |-
                #!/bin/sh
                set -eu
                mkdir -m 0777 -p "$VOL_DIR"
                chmod 700 "$VOL_DIR/.."
              teardown: |-
                #!/bin/sh
                set -eu
                rm -rf "$VOL_DIR"
              helperPod.yaml: |-
                apiVersion: v1
                kind: Pod
                metadata:
                  name: helper-pod
                spec:
                  containers:
                    - name: helper-pod
                      image: rancher/mirrored-library-busybox:1.36.1
                      imagePullPolicy: IfNotPresent
          '';
        in [
          "d /var/lib/rancher/k3s/server/manifests 0755 root root -"
          "L+ /var/lib/rancher/k3s/server/manifests/local-path-provisioner.yaml - - - - ${localPathManifest}"
        ]
      );

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