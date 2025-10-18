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
      ./hardware-configuration.nix
      inputs.proxmox-nixos.nixosModules.proxmox-ve
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
  ];

  # Create /usr/bin symlinks for tools that expect standard FHS paths
  # Required for Proxmox Pulumi provider which uses /usr/bin/tee
  system.activationScripts.usrbintools = ''
    mkdir -m 0755 -p /usr/bin
    ln -sfn ${pkgs.coreutils}/bin/tee /usr/bin/tee
    ln -sfn ${pkgs.bash}/bin/bash /usr/bin/bash
  '';

  # Configure sudo for Proxmox Pulumi provider
  # Provider v0.48.0+ requires specific sudo permission for file uploads
  # See: https://github.com/bpg/terraform-provider-proxmox/releases/tag/v0.48.0
  security.sudo.extraRules = [
    {
      users = [ "max" ];
      commands = [
        {
          command = "/usr/bin/tee /var/lib/vz/*";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Enable the OpenSSH daemon
  services.openssh.openFirewall = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. Don't change this unless you know what you're doing.
  system.stateVersion = "24.11"; # Did you read the comment?
}
