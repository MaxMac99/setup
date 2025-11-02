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

  # Prevent Proxmox services from restarting during nixos-rebuild
  # This keeps VMs running during system updates
  systemd.services = {
    "pve-cluster".restartIfChanged = false;
    "pve-ha-crm".restartIfChanged = false;
    "pve-ha-lrm".restartIfChanged = false;
    "pvedaemon".restartIfChanged = false;
    "pveproxy".restartIfChanged = false;
    "pvestatd".restartIfChanged = false;
    "pvescheduler".restartIfChanged = false;
    "pve-firewall".restartIfChanged = false;
    "pve-lxc-syscalld".restartIfChanged = false;
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

  # Enable Cockpit for web-based system management (alternative to Proxmox UI)
  services.cockpit = {
    enable = true;
    port = 9090;
    settings = {
      WebService = {
        AllowUnencrypted = true;
        # Allow connections from any origin (local network access)
        Origins = lib.mkForce "http://192.168.178.2:9090 http://maxdata:9090 http://maxdata.local:9090 https://192.168.178.2:9090";
      };
    };
  };

  # Enable Prometheus node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    # Enable comprehensive collectors for storage server monitoring
    enabledCollectors = [
      "systemd"      # Systemd units and services
      "zfs"          # ZFS pools, datasets, ARC stats
      "filesystem"   # Filesystem usage and stats
      "diskstats"    # Disk I/O statistics
      "smartmon"     # SMART disk health metrics
      "nfs"          # NFS server statistics
      "nfsd"         # NFS daemon statistics
      "processes"    # Process statistics
      "interrupts"   # Hardware interrupts
      "textfile"     # Custom metrics from text files
    ];
  };
}
