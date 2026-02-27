{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/profiles/core-user"
      "modules/profiles/development.nix"
      "modules/profiles/gcloud.nix"
      "modules/profiles/full-nvim.nix"
      "modules/profiles/personal-ssh.nix"
    ])
    ++ [
      inputs.zfs-exporter.nixosModules.default
      ./networking.nix
      ./zfs.nix
      ./smb.nix
      ./monitoring.nix
      ./hardware-configuration.nix
      ./microvms.nix
      ./microvm-bridge.nix
    ];

  hostSpec = {
    username = "max";
    hostName = "maxdata";
  };

  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
    # Use stable kernel for ZFS compatibility
    kernelPackages = pkgs.linuxPackages;

    # ZFS
    supportedFilesystems = ["zfs"];
    zfs = {
      devNodes = "/dev/disk/by-id";
    };

    # ZFS ARC tuning for 32GB RAM (18GB reserved for 3x 6GB microVMs)
    kernelParams = [
      "zfs.zfs_arc_max=8589934592" # 8GB ARC max
      "zfs.zfs_arc_min=2147483648" # 2GB ARC min
    ];
    extraModprobeConfig = ''
      options zfs zfs_arc_max=8589934592
      options zfs zfs_arc_min=2147483648
    '';
  };

  # CRITICAL: Required for ZFS
  networking.hostId = "ec7b6b2d";

  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
  };

  # NFS server for K3s persistent volumes
  services.nfs.server = {
    enable = true;
    exports = ''
      /tank/k8s/nfs 192.168.178.0/24(rw,sync,no_subtree_check,no_root_squash)
      /tank/k8s/timemachine 192.168.178.0/24(rw,async,no_subtree_check,no_root_squash)
    '';
  };

  # System packages
  environment.systemPackages = with pkgs; [
    zfs
    sanoid

    # Network tools
    iperf3
    nmap
    tcpdump

    # System monitoring
    lm_sensors
    smartmontools
    nvme-cli

    # Backup tools
    rclone

    # Kubernetes tools
    kubectl
    kubernetes-helm
    k9s
  ];

  # Enable the OpenSSH daemon with emergency mode support
  services.openssh = {
    openFirewall = true;
    startWhenNeeded = false; # Always start, don't wait for socket activation
  };

  # Keep SSH running even in emergency/rescue mode
  systemd.services.sshd = {
    unitConfig = {
      IgnoreOnIsolate = true; # Don't stop SSH when switching to emergency mode
    };
    wantedBy = lib.mkForce ["multi-user.target" "emergency.target" "rescue.target"];
    serviceConfig = {
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Increase timeouts to prevent premature emergency mode
  systemd.settings.Manager = {
    DefaultTimeoutStartSec = "300s";
    DefaultTimeoutStopSec = "30s";
  };

  system.stateVersion = "24.11";
}