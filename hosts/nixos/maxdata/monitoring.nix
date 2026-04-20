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

  # Grafana Alloy - Log shipping to Loki (replaces promtail)
  services.alloy = {
    enable = true;
    extraFlags = ["--disable-reporting"];
  };

  environment.etc."alloy/config.alloy".text = ''
    // System journal logs
    loki.source.journal "journal" {
      forward_to    = [loki.relabel.journal.receiver]
      max_age       = "12h"
      labels        = {
        job  = "systemd-journal",
        host = "maxdata",
      }
    }

    loki.relabel "journal" {
      forward_to = [loki.write.loki.receiver]

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "hostname"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    // Samba logs
    local.file_match "samba" {
      path_targets = [{
        __path__ = "/var/log/samba/*.log",
        job      = "samba",
        host     = "maxdata",
      }]
    }

    loki.source.file "samba" {
      targets    = local.file_match.samba.targets
      forward_to = [loki.write.loki.receiver]
    }

    // Send logs to Loki in Kubernetes cluster
    loki.write "loki" {
      endpoint {
        url = "http://192.168.178.11:3100/loki/api/v1/push"
      }
    }
  '';

  # SMART monitoring daemon - automated self-tests and health checks
  # Create notification script for smartd
  environment.etc."smartd-notify.sh" = {
    text = ''
      #!/bin/sh
      # Smartd notification script - logs to systemd journal
      echo "SMART Alert on $SMARTD_DEVICE: $SMARTD_FAILTYPE - $SMARTD_MESSAGE" | \
        ${pkgs.systemd}/bin/systemd-cat -t smartd -p warning
    '';
    mode = "0755";
  };

  services.smartd = {
    enable = true;
    # Don't send emails, we'll use systemd journal and Prometheus alerts instead
    notifications = {
      mail.enable = false;
      wall.enable = false;
    };
    # Monitor all devices with comprehensive settings
    defaults.monitored = ''
      -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,35,45 -m root -M exec /etc/smartd-notify.sh
    '';
    # Explanation of flags:
    # -a: Monitor all SMART attributes
    # -o on: Enable automatic offline tests
    # -S on: Enable attribute autosave
    # -n standby,q: Don't wake up sleeping disks
    # -s (S/../.././02|L/../../6/03): Run short test daily at 2am, long test every Saturday at 3am
    # -W 4,35,45: Warn on temp change of 4°C, or temp below 35°C or above 45°C
    # -m root: Send to root
    # -M exec: Execute notification script
  };

  # Enable Prometheus node exporter for monitoring
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9100;
      # Enable comprehensive collectors for storage server monitoring
      enabledCollectors = [
        "systemd" # Systemd units and services
        "filesystem" # Filesystem usage and stats
        "diskstats" # Disk I/O statistics
        "nfs" # NFS server statistics
        "nfsd" # NFS daemon statistics
        "processes" # Process statistics
        "interrupts" # Hardware interrupts
      ];
    };
    smartctl = {
      enable = true;
      port = 9116;
    };
  };

  # Ensure log directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter 0755 root root -"
  ];
}
