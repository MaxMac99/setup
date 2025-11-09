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

  # ZFS pool metrics via textfile collector
  # Exports pool capacity, health, and fragmentation metrics
  systemd.services.zfs-textfile = {
    description = "Collect ZFS pool metrics for Prometheus node_exporter";
    script = ''
      set -euo pipefail

      TEXTFILE_DIR="/var/lib/prometheus-node-exporter"
      TEMP_FILE="$TEXTFILE_DIR/zfs.prom.$$"
      OUTPUT_FILE="$TEXTFILE_DIR/zfs.prom"

      mkdir -p "$TEXTFILE_DIR"

      # Write metrics header
      cat > "$TEMP_FILE" <<EOF
      # HELP node_zfs_zpool_state ZFS pool state (online=1, degraded=2, faulted=3, offline=4, removed=5, unavail=6)
      # TYPE node_zfs_zpool_state gauge
      # HELP node_zfs_zpool_size_bytes Total size of the ZFS pool in bytes
      # TYPE node_zfs_zpool_size_bytes gauge
      # HELP node_zfs_zpool_allocated_bytes Allocated space in the ZFS pool in bytes
      # TYPE node_zfs_zpool_allocated_bytes gauge
      # HELP node_zfs_zpool_free_bytes Free space in the ZFS pool in bytes
      # TYPE node_zfs_zpool_free_bytes gauge
      # HELP node_zfs_zpool_fragmentation_percent Pool fragmentation percentage
      # TYPE node_zfs_zpool_fragmentation_percent gauge
      # HELP node_zfs_zpool_capacity_percent Pool capacity used percentage
      # TYPE node_zfs_zpool_capacity_percent gauge
      # HELP node_zfs_zpool_health Pool health status (ONLINE=0, DEGRADED=1, FAULTED=2, OFFLINE=3, UNAVAIL=4, REMOVED=5)
      # TYPE node_zfs_zpool_health gauge
      # HELP node_zfs_zpool_resilver_active Resilver operation in progress (1=active, 0=not active)
      # TYPE node_zfs_zpool_resilver_active gauge
      # HELP node_zfs_zpool_resilver_percent Resilver progress percentage
      # TYPE node_zfs_zpool_resilver_percent gauge
      # HELP node_zfs_zpool_resilver_bytes_scanned Bytes scanned during resilver
      # TYPE node_zfs_zpool_resilver_bytes_scanned gauge
      # HELP node_zfs_zpool_resilver_bytes_issued Bytes issued during resilver
      # TYPE node_zfs_zpool_resilver_bytes_issued gauge
      # HELP node_zfs_zpool_resilver_bytes_total Total bytes to resilver
      # TYPE node_zfs_zpool_resilver_bytes_total gauge
      # HELP node_zfs_zpool_resilver_seconds_remaining Estimated seconds remaining for resilver
      # TYPE node_zfs_zpool_resilver_seconds_remaining gauge
      # HELP node_zfs_zpool_scrub_active Scrub operation in progress (1=active, 0=not active)
      # TYPE node_zfs_zpool_scrub_active gauge
      # HELP node_zfs_zpool_read_errors Total read errors on pool
      # TYPE node_zfs_zpool_read_errors gauge
      # HELP node_zfs_zpool_write_errors Total write errors on pool
      # TYPE node_zfs_zpool_write_errors gauge
      # HELP node_zfs_zpool_checksum_errors Total checksum errors on pool
      # TYPE node_zfs_zpool_checksum_errors gauge
      # HELP node_zfs_device_read_errors Read errors per device
      # TYPE node_zfs_device_read_errors gauge
      # HELP node_zfs_device_write_errors Write errors per device
      # TYPE node_zfs_device_write_errors gauge
      # HELP node_zfs_device_checksum_errors Checksum errors per device
      # TYPE node_zfs_device_checksum_errors gauge
      EOF

      # Get list of pools
      POOLS=$(${pkgs.zfs}/bin/zpool list -H -o name)

      for pool in $POOLS; do
        # Get pool properties
        SIZE=$(${pkgs.zfs}/bin/zpool list -H -o size -p "$pool")
        ALLOC=$(${pkgs.zfs}/bin/zpool list -H -o allocated -p "$pool")
        FREE=$(${pkgs.zfs}/bin/zpool list -H -o free -p "$pool")
        FRAG=$(${pkgs.zfs}/bin/zpool list -H -o fragmentation "$pool" | ${pkgs.gnused}/bin/sed 's/%$//' | ${pkgs.gnused}/bin/sed 's/-/0/')
        CAP=$(${pkgs.zfs}/bin/zpool list -H -o capacity "$pool" | ${pkgs.gnused}/bin/sed 's/%$//')
        HEALTH=$(${pkgs.zfs}/bin/zpool list -H -o health "$pool")

        # Convert health to numeric value
        case "$HEALTH" in
          ONLINE) HEALTH_VAL=0 ;;
          DEGRADED) HEALTH_VAL=1 ;;
          FAULTED) HEALTH_VAL=2 ;;
          OFFLINE) HEALTH_VAL=3 ;;
          UNAVAIL) HEALTH_VAL=4 ;;
          REMOVED) HEALTH_VAL=5 ;;
          *) HEALTH_VAL=99 ;;
        esac

        # Write basic metrics
        echo "node_zfs_zpool_size_bytes{zpool=\"$pool\"} $SIZE" >> "$TEMP_FILE"
        echo "node_zfs_zpool_allocated_bytes{zpool=\"$pool\"} $ALLOC" >> "$TEMP_FILE"
        echo "node_zfs_zpool_free_bytes{zpool=\"$pool\"} $FREE" >> "$TEMP_FILE"
        echo "node_zfs_zpool_fragmentation_percent{zpool=\"$pool\"} $FRAG" >> "$TEMP_FILE"
        echo "node_zfs_zpool_capacity_percent{zpool=\"$pool\"} $CAP" >> "$TEMP_FILE"
        echo "node_zfs_zpool_health{zpool=\"$pool\"} $HEALTH_VAL" >> "$TEMP_FILE"

        # Check for resilver/scrub status
        STATUS=$(${pkgs.zfs}/bin/zpool status "$pool")

        # Check for active resilver
        if echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -q "resilver in progress"; then
          echo "node_zfs_zpool_resilver_active{zpool=\"$pool\"} 1" >> "$TEMP_FILE"

          # Extract resilver progress percentage
          RESILVER_PCT=$(echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -oP '\d+\.\d+% done' | ${pkgs.gnugrep}/bin/grep -oP '\d+\.\d+' || echo "0")
          echo "node_zfs_zpool_resilver_percent{zpool=\"$pool\"} $RESILVER_PCT" >> "$TEMP_FILE"

          # Extract scanned and total bytes from format: "2.70T / 4.98T scanned"
          SCAN_LINE=$(echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -oP '[\d\.]+[KMGTP]? / [\d\.]+[KMGTP]? scanned' || echo "")
          if [ -n "$SCAN_LINE" ]; then
            # Extract scanned (first number)
            SCANNED=$(echo "$SCAN_LINE" | ${pkgs.gawk}/bin/awk '{print $1}')
            SCANNED_BYTES=$(echo "$SCANNED" | ${pkgs.gnused}/bin/sed 's/K/*1024/; s/M/*1048576/; s/G/*1073741824/; s/T/*1099511627776/; s/P/*1125899906842624/' | ${pkgs.bc}/bin/bc 2>/dev/null || echo "0")
            # Extract total (third number, after the /)
            TOTAL=$(echo "$SCAN_LINE" | ${pkgs.gawk}/bin/awk '{print $3}')
            TOTAL_BYTES=$(echo "$TOTAL" | ${pkgs.gnused}/bin/sed 's/K/*1024/; s/M/*1048576/; s/G/*1073741824/; s/T/*1099511627776/; s/P/*1125899906842624/' | ${pkgs.bc}/bin/bc 2>/dev/null || echo "0")
          else
            SCANNED_BYTES="0"
            TOTAL_BYTES="0"
          fi
          echo "node_zfs_zpool_resilver_bytes_scanned{zpool=\"$pool\"} $SCANNED_BYTES" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_bytes_total{zpool=\"$pool\"} $TOTAL_BYTES" >> "$TEMP_FILE"

          # Extract issued bytes from format: "998G / 4.96T issued"
          ISSUED_LINE=$(echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -oP '[\d\.]+[KMGTP]? / [\d\.]+[KMGTP]? issued' || echo "")
          if [ -n "$ISSUED_LINE" ]; then
            ISSUED=$(echo "$ISSUED_LINE" | ${pkgs.gawk}/bin/awk '{print $1}')
            ISSUED_BYTES=$(echo "$ISSUED" | ${pkgs.gnused}/bin/sed 's/K/*1024/; s/M/*1048576/; s/G/*1073741824/; s/T/*1099511627776/; s/P/*1125899906842624/' | ${pkgs.bc}/bin/bc 2>/dev/null || echo "0")
          else
            ISSUED_BYTES="0"
          fi
          echo "node_zfs_zpool_resilver_bytes_issued{zpool=\"$pool\"} $ISSUED_BYTES" >> "$TEMP_FILE"

          # Extract time remaining from format: "02:39:37 to go" (HH:MM:SS)
          TIME_STR=$(echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -oP '\d+:\d+:\d+ to go' | ${pkgs.gawk}/bin/awk '{print $1}' || echo "")
          if [ -n "$TIME_STR" ]; then
            # Split HH:MM:SS
            HOURS=$(echo "$TIME_STR" | ${pkgs.gawk}/bin/awk -F: '{print $1}')
            MINS=$(echo "$TIME_STR" | ${pkgs.gawk}/bin/awk -F: '{print $2}')
            SECS=$(echo "$TIME_STR" | ${pkgs.gawk}/bin/awk -F: '{print $3}')
            SECONDS=$((HOURS * 3600 + MINS * 60 + SECS))
          else
            SECONDS="0"
          fi
          echo "node_zfs_zpool_resilver_seconds_remaining{zpool=\"$pool\"} $SECONDS" >> "$TEMP_FILE"
        else
          echo "node_zfs_zpool_resilver_active{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_percent{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_bytes_scanned{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_bytes_issued{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_bytes_total{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          echo "node_zfs_zpool_resilver_seconds_remaining{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
        fi

        # Check for active scrub
        if echo "$STATUS" | ${pkgs.gnugrep}/bin/grep -q "scrub in progress"; then
          echo "node_zfs_zpool_scrub_active{zpool=\"$pool\"} 1" >> "$TEMP_FILE"
        else
          echo "node_zfs_zpool_scrub_active{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
        fi

        # Extract error counts from zpool status
        # Get the pool-level errors (shown in the "errors:" line at the bottom)
        POOL_ERRORS=$(echo "$STATUS" | ${pkgs.gnugrep}/bin/grep "^errors:")
        if [ -n "$POOL_ERRORS" ]; then
          # If errors line says "No known data errors" set all to 0
          if echo "$POOL_ERRORS" | ${pkgs.gnugrep}/bin/grep -q "No known data errors"; then
            echo "node_zfs_zpool_read_errors{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
            echo "node_zfs_zpool_write_errors{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
            echo "node_zfs_zpool_checksum_errors{zpool=\"$pool\"} 0" >> "$TEMP_FILE"
          fi
        fi

        # Parse device-level errors from the status output
        # Format: device_name  STATE  READ WRITE CKSUM
        echo "$STATUS" | ${pkgs.gawk}/bin/awk -v pool="$pool" '
          # Skip header lines and pool name line
          /^[[:space:]]*(NAME|'$pool'|state:|scan:|config:|errors:)/ { next }
          # Skip empty lines
          /^[[:space:]]*$/ { next }
          # Skip resilver/scrub status lines
          /resilver|scanned|issued|done|to go/ { next }
          # Match device lines with error counts
          /^[[:space:]]+[a-zA-Z0-9_\-\/]+[[:space:]]+[A-Z]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+/ {
            # Extract device name (remove leading spaces)
            device = $1
            # Skip if device name contains certain keywords that arent actual devices
            if (device ~ /mirror|raidz|spare|cache|log/) next

            # Get error columns (columns vary based on indentation)
            # Look for the pattern: ONLINE/DEGRADED/etc followed by 3 numbers
            for (i = 2; i <= NF-2; i++) {
              if ($i ~ /^(ONLINE|DEGRADED|OFFLINE|FAULTED|UNAVAIL|REMOVED)$/) {
                read_err = $(i+1)
                write_err = $(i+2)
                cksum_err = $(i+3)

                print "node_zfs_device_read_errors{zpool=\"" pool "\",device=\"" device "\"} " read_err
                print "node_zfs_device_write_errors{zpool=\"" pool "\",device=\"" device "\"} " write_err
                print "node_zfs_device_checksum_errors{zpool=\"" pool "\",device=\"" device "\"} " cksum_err
                break
              }
            }
          }
        ' >> "$TEMP_FILE"
      done

      # Atomically replace the output file
      mv "$TEMP_FILE" "$OUTPUT_FILE"
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  # Run ZFS pool metrics collection every minute
  systemd.timers.zfs-textfile = {
    description = "Timer for ZFS pool metrics collection";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "1min";
      Persistent = true;
    };
  };

  # Ensure the textfile directory exists
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter 0755 root root -"
  ];
}
