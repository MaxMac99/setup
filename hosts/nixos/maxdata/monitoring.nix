{
  config,
  lib,
  pkgs,
  ...
}: {
  # ZFS Prometheus Exporter
  services.zfs-prometheus-exporter = {
    enable = true;
    port = 9134;
    openFirewall = true;
    logLevel = "debug";
    logFormat = "json";
  };

  # Promtail - Log shipping to Loki
  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_port = 3031;
        grpc_listen_port = 0;
      };

      # Send logs to Loki LoadBalancer in Kubernetes cluster
      clients = [
        {
          url = "http://192.168.178.11:3100/loki/api/v1/push";
        }
      ];

      positions = {
        filename = "/var/lib/promtail/positions.yaml";
      };

      scrape_configs = [
        # System journal logs
        {
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = "maxdata";
            };
          };
          relabel_configs = [
            {
              source_labels = ["__journal__systemd_unit"];
              target_label = "unit";
            }
            {
              source_labels = ["__journal__hostname"];
              target_label = "hostname";
            }
            {
              source_labels = ["__journal_priority_keyword"];
              target_label = "level";
            }
          ];
        }

        # Proxmox logs
        {
          job_name = "proxmox";
          static_configs = [
            {
              targets = ["localhost"];
              labels = {
                job = "proxmox";
                host = "maxdata";
                __path__ = "/var/log/pve/**/*.log";
              };
            }
          ];
        }

        # Samba logs
        {
          job_name = "samba";
          static_configs = [
            {
              targets = ["localhost"];
              labels = {
                job = "samba";
                host = "maxdata";
                __path__ = "/var/log/samba/*.log";
              };
            }
          ];
        }
      ];
    };
  };

  # Enable Prometheus node exporter for monitoring
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    # Enable comprehensive collectors for storage server monitoring
    enabledCollectors = [
      "systemd"      # Systemd units and services
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

  # Open firewall for Promtail HTTP (for status/metrics)
  networking.firewall.allowedTCPPorts = [
    3031 # Promtail HTTP
  ];

  # Ensure log directories and promtail state directory exist
  systemd.tmpfiles.rules = [
    "d /var/log/pve 0755 root root -"
    "d /var/lib/prometheus-node-exporter 0755 root root -"
    "d /var/lib/promtail 0755 promtail promtail -"
  ];
}
