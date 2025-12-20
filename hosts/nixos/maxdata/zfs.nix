{
  config,
  lib,
  pkgs,
  ...
}: {
  # ZFS services
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
      pools = ["tank" "fast"];
    };

    autoSnapshot = {
      enable = false; # Managed by sanoid
    };

    trim = {
      enable = true;
      interval = "weekly";
    };
  };

  # Sanoid for advanced snapshot management
  services.sanoid = {
    enable = true;
    datasets = {
      "tank/pve" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "tank/data" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "fast/pve" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "fast/root" = {
        useTemplate = ["production"];
      };
      "fast/k8s" = {
        useTemplate = ["production"];
        recursive = true;
      };
    };
    templates.production = {
      frequently = 0;
      hourly = 48;
      daily = 30;
      monthly = 6;
      yearly = 0;
      autosnap = true;
      autoprune = true;
    };
  };

  # Syncoid for replication (fast → tank backup)
  services.syncoid = {
    enable = true;
    commands."fast-pve-to-tank" = {
      source = "fast/pve";
      target = "tank/fast-backup/pve";
      recursive = true;
      sendOptions = "w";
    };
    commands."fast-k8s-to-tank" = {
      source = "fast/k8s";
      target = "tank/fast-backup/k8s";
      recursive = true;
      sendOptions = "w";
    };
  };

  # ZFS Event Daemon - immediate notifications on pool events
  services.zfs.zed = {
    enableMail = false; # We'll use systemd journal and Prometheus alerts instead
    settings = {
      # Logging
      ZED_DEBUG_LOG = "/var/log/zed.debug.log";
      ZED_SYSLOG_TAG = "zed";

      # Use systemd notification instead of email
      ZED_NOTIFY_VERBOSE = "1";
      ZED_NOTIFY_DATA = "1";

      # Auto-scrub after resilver completes
      ZED_SCRUB_AFTER_RESILVER = "1";

      # Spare disk handling (if you have hot spares)
      ZED_SPARE_ON_IO_ERRORS = "0"; # Set to 1 if you have spare disks configured
      ZED_SPARE_ON_CHECKSUM_ERRORS = "0"; # Set to 1 if you have spare disks configured
    };
  };

  # Systemd service for monitoring ZFS pool health
  systemd.services.zfs-health-check = {
    description = "Check ZFS pool health";
    script = ''
      pools="tank fast"
      for pool in $pools; do
        status=$(${pkgs.zfs}/bin/zpool status $pool | ${pkgs.gnugrep}/bin/grep state | ${pkgs.gawk}/bin/awk '{print $2}')
        if [ "$status" != "ONLINE" ]; then
          echo "WARNING: Pool $pool is $status"
          # Add notification here (email, ntfy, etc.)
        fi
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers.zfs-health-check = {
    description = "Timer for ZFS health check";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # ZFS kernel module settings
  boot.extraModprobeConfig = ''
    # Enable zstd compression support
    options zfs zfs_compressed_arc_enabled=1

    # Tune prefetch for better performance
    options zfs zfs_prefetch_disable=0
    options zfs l2arc_write_max=104857600
    options zfs l2arc_write_boost=209715200
  '';

  # Performance tuning via /etc/modprobe.d/ for persistence
  environment.etc."modprobe.d/zfs.conf".text = ''
    options zfs zfs_arc_max=17179869184
    options zfs zfs_arc_min=4294967296
    options zfs zfs_compressed_arc_enabled=1
    options zfs l2arc_write_max=104857600
    options zfs l2arc_write_boost=209715200
  '';
}
