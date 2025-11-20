{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports =
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "hosts/common/optional/nixos/openssh.nix"
    ])
    ++ [
      ./networking.nix
      ./proxmox.nix
      ./zfs.nix
      ./smb.nix
      ./monitoring.nix
      ./hardware-configuration.nix
      ./microvms.nix
      ./microvm-bridge.nix
      inputs.proxmox-nixos.nixosModules.proxmox-ve
      inputs.zfs-exporter.nixosModules.default
    ];

  nixpkgs.overlays = [
    inputs.proxmox-nixos.overlays.x86_64-linux
  ];

  hostSpec = {
    username = "max";
    hostName = "maxdata";
    isDarwin = false;
    isWork = false;
    isServer = true;
    isMinimal = false;
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

    # ZFS ARC tuning for 32GB RAM
    kernelParams = [
      "zfs.zfs_arc_max=17179869184" # 16GB ARC max
      "zfs.zfs_arc_min=4294967296" # 4GB ARC min
    ];
    extraModprobeConfig = ''
      options zfs zfs_arc_max=17179869184
      options zfs zfs_arc_min=4294967296
    '';
  };

  # CRITICAL: Required for ZFS
  networking.hostId = "ec7b6b2d"; # Generate your own with: head -c 8 /dev/urandom | od -A n -t x8 | tr -d ' '

  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
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
    startWhenNeeded = false;  # Always start, don't wait for socket activation
  };

  # Keep SSH running even in emergency/rescue mode
  systemd.services.sshd = {
    unitConfig = {
      IgnoreOnIsolate = true;  # Don't stop SSH when switching to emergency mode
    };
    wantedBy = lib.mkForce [ "multi-user.target" "emergency.target" "rescue.target" ];
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. Don't change this unless you know what you're doing.
  system.stateVersion = "24.11"; # Did you read the comment?
}
