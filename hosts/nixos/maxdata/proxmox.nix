{
  config,
  lib,
  pkgs,
  ...
}: {
  # Proxmox VE configuration (provided by proxmox-nixos module)
  services.proxmox-ve = {
    enable = true;

    # Network configuration for Proxmox
    # This integrates with the bridge we created in networking.nix
    ipAddress = "192.168.178.2"; # Adjust to your IP or leave empty for DHCP
  };

  # Packages required for Proxmox VMs
  environment.systemPackages = with pkgs; [
    swtpm # TPM emulator for Windows 11 VMs
  ];

  # Additional Proxmox-related services

  # Enable NFS server for VM storage sharing (optional, for K3S)
  services.nfs.server = {
    enable = true;
    exports = ''
      # Export for K3S persistent volumes
      /tank/k8s/nfs 192.168.178.0/24(rw,sync,no_subtree_check,no_root_squash)
      # Export for Time Machine backup service in K3S
      /tank/k8s/timemachine 192.168.178.0/24(rw,async,no_subtree_check,no_root_squash)
    '';
  };

  # Samba for Windows file sharing (optional)
  # services.samba = {
  #   enable = true;
  #   securityType = "user";
  #   shares = {
  #     tank = {
  #       path = "/tank/data";
  #       browseable = "yes";
  #       "read only" = "no";
  #       "guest ok" = "no";
  #       "create mask" = "0644";
  #       "directory mask" = "0755";
  #     };
  #   };
  # };

  # Enable Cockpit for web-based system management (alternative to Proxmox UI)
  services.cockpit = {
    enable = true;
    port = 9090;
    settings = {
      WebService = {
        AllowUnencrypted = true;
      };
    };
  };

  # Enable Prometheus node exporter for monitoring (optional)
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = ["systemd" "zfs"];
  };

  # Time Machine support via Samba (optional, for Mac backups)
  # services.samba-wsdd.enable = true; # For Windows network discovery
  # services.samba.extraConfig = ''
  #   [Time Machine]
  #   path = /tank/timemachine
  #   valid users = max
  #   read only = no
  #   vfs objects = catia fruit streams_xattr
  #   fruit:time machine = yes
  #   fruit:time machine max size = 500G
  # '';
}
