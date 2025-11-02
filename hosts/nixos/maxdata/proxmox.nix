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
      "nfs"          # NFS server statistics
      "nfsd"         # NFS daemon statistics
      "processes"    # Process statistics
      "interrupts"   # Hardware interrupts
      "textfile"     # Custom metrics from text files (for SMART data)
    ];
    # Textfile collector directory for SMART metrics
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter"
    ];
  };

  # SMART disk monitoring via textfile collector
  # Runs smartctl and exports metrics for Prometheus
  systemd.services.smartmon-textfile = {
    description = "Collect SMART metrics for Prometheus node_exporter";
    script = ''
      set -euo pipefail

      TEXTFILE_DIR="/var/lib/prometheus-node-exporter"
      TEMP_FILE="$TEXTFILE_DIR/smartmon.prom.$$"
      OUTPUT_FILE="$TEXTFILE_DIR/smartmon.prom"

      mkdir -p "$TEXTFILE_DIR"

      # Get all disk devices (excluding loop and ram devices)
      DEVICES=$(${pkgs.util-linux}/bin/lsblk -d -n -o NAME,TYPE | ${pkgs.gawk}/bin/awk '$2=="disk" {print $1}')

      # Write metrics header
      cat > "$TEMP_FILE" <<EOF
      # HELP smartmon_device_active SMART device is active (1) or not (0)
      # TYPE smartmon_device_active gauge
      # HELP smartmon_temperature_celsius_value SMART temperature in Celsius
      # TYPE smartmon_temperature_celsius_value gauge
      # HELP smartmon_power_on_hours_value SMART power on hours
      # TYPE smartmon_power_on_hours_value gauge
      # HELP smartmon_wear_leveling_count_value SMART wear leveling count (SSD)
      # TYPE smartmon_wear_leveling_count_value gauge
      # HELP smartmon_reallocated_sector_ct_value SMART reallocated sectors count
      # TYPE smartmon_reallocated_sector_ct_value gauge
      # HELP smartmon_current_pending_sector_value SMART current pending sectors
      # TYPE smartmon_current_pending_sector_value gauge
      EOF

      for device in $DEVICES; do
        # Check if SMART is available on this device
        if ${pkgs.smartmontools}/bin/smartctl -i /dev/$device >/dev/null 2>&1; then
          echo "smartmon_device_active{device=\"$device\"} 1" >> "$TEMP_FILE"

          # Get SMART attributes
          ${pkgs.smartmontools}/bin/smartctl -A /dev/$device | ${pkgs.gawk}/bin/awk -v device="$device" '
            /Temperature_Celsius/ { print "smartmon_temperature_celsius_value{device=\"" device "\"} " $10 }
            /Power_On_Hours/ { print "smartmon_power_on_hours_value{device=\"" device "\"} " $10 }
            /Wear_Leveling_Count/ { print "smartmon_wear_leveling_count_value{device=\"" device "\"} " $10 }
            /Reallocated_Sector_Ct/ { print "smartmon_reallocated_sector_ct_value{device=\"" device "\"} " $10 }
            /Current_Pending_Sector/ { print "smartmon_current_pending_sector_value{device=\"" device "\"} " $10 }
          ' >> "$TEMP_FILE" 2>/dev/null || true
        else
          echo "smartmon_device_active{device=\"$device\"} 0" >> "$TEMP_FILE"
        fi
      done

      # Atomically replace the output file
      mv "$TEMP_FILE" "$OUTPUT_FILE"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  # Run SMART monitoring every 5 minutes
  systemd.timers.smartmon-textfile = {
    description = "Timer for SMART metrics collection";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };

  # Ensure the textfile directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter 0755 root root -"
  ];
}
