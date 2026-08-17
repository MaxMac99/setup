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
      "tank/data" = {
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
      # Family data — was templated but never applied (Phase 11). daten-max/
      # michael/anna are empty today; covered anyway so a future write is
      # snapshotted from day one rather than after someone notices.
      "tank/daten-familie" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "tank/daten-max" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "tank/daten-michael" = {
        useTemplate = ["production"];
        recursive = true;
      };
      "tank/daten-anna" = {
        useTemplate = ["production"];
        recursive = true;
      };
      # NFS exports (Paperless media etc.) and the unmounted timemachine
      # child both live under here.
      "tank/k8s" = {
        useTemplate = ["production"];
        recursive = true;
      };
      # Syncoid's receive side. autosnap=false: sanoid must never originate
      # snapshots here, only prune the ones syncoid replicates in — the
      # source (fast/k8s) already owns retention. Without this, syncoid's
      # own snapshots never get pruned; this dataset carried 13 690 of them.
      "tank/fast-backup/k8s" = {
        useTemplate = ["backupTarget"];
        recursive = true;
      };
      "tank/brink-backup/k8s" = {
        useTemplate = ["backupTarget"];
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
    templates.backupTarget = {
      frequently = 0;
      hourly = 48;
      daily = 30;
      monthly = 6;
      yearly = 0;
      autosnap = false;
      autoprune = true;
    };
  };

  # Phase 11: brink-server's private key for the syncoid pull below.
  # brink-server itself only ever sees the public half (hosts/nixos/brink-server/backup.nix).
  sops.secrets."syncoid_brink_key" = {
    sopsFile = lib.custom.relativeToRoot "secrets/backup.yaml";
    owner = "syncoid";
  };

  # syncoid runs as its own system user with its own $HOME, which has no
  # known_hosts of its own — StrictHostKeyChecking fails the pull on every
  # run, not just the first, until this exists. Pinned by address rather than
  # `brink-server.mesh.mvissing.de`, since this is the overlay identity, not
  # the DNS one, and the two are independent claims. Read directly off the
  # box (`/etc/ssh/ssh_host_ed25519_key.pub`) and cross-checked against
  # `ssh-keyscan` over the overlay, 2026-08-15.
  programs.ssh.knownHosts."brink-server-overlay" = {
    hostNames = [config.networkConfig.hosts.brink-server.overlayIPv4];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDFTX9KWUSx/YCjiYBLmoIHMrPKp773Noal0xG0B4uWn";
  };

  # `zfs receive` creates the leaf target but never a missing *parent* —
  # `tank/fast-backup` already existed when that syncoid target was set up,
  # but `tank/brink-backup` did not, and the first live run failed with
  # "cannot open 'tank/brink-backup': dataset does not exist" until this
  # existed. `-p` makes it idempotent across rebuilds, like `mkdir -p`.
  systemd.services.tank-brink-backup-parent = {
    description = "Ensure tank/brink-backup exists for the syncoid pull to receive into";
    after = ["zfs.target"];
    before = ["syncoid-brink-k8s-to-tank.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/booted-system/sw/bin/zfs create -p tank/brink-backup";
    };
  };

  # Syncoid for replication (fast → tank backup, and brink-server → tank
  # off-box). Both targets are pruned by services.sanoid's backupTarget
  # template above — which only ever recognises sanoid's own
  # `autosnap_*_{hourly,daily,...}` naming. Without --no-sync-snap, syncoid
  # creates its own uniquely-named marker snapshot on the *source* every run
  # and replicates it in; the source stays lean because syncoid cleans up its
  # own old markers there, but the copies already sent to the target are
  # invisible to sanoid's pruning and never leave. That is exactly the
  # unbounded-target bug this phase exists to fix, so both source datasets
  # (fast/k8s here, main/k8s on brink-server) now carry their own sanoid
  # schedule, and --no-sync-snap makes syncoid use those existing snapshots
  # as sync points instead of minting new unprunable ones.
  #
  # ⚠️ Discovered live, not in review: the first version of brink-k8s-to-tank
  # shipped without this, and 26 minutes of `sanoid --cron` on 2026-08-15
  # only pruned 86 of ~7000 snapshots on tank/fast-backup/k8s — the 86 that
  # matched sanoid's naming. The other ~6900 were exactly this.
  services.syncoid = {
    enable = true;
    commonArgs = ["--no-sync-snap"];
    # The module's own default omits "destroy" here — reasonable for a target
    # that is *only* ever received into, but syncoid also wants it to clean up
    # its own stale syncoid_* markers on the target once they are no longer
    # needed as sync points. Without it, that cleanup fails permission-denied
    # every run (seen live, 2026-08-15) and the ~6900-snapshot backlog this
    # phase exists to fix never actually drains.
    localTargetAllow = [
      "change-key"
      "compression"
      "create"
      "destroy"
      "mount"
      "mountpoint"
      "receive"
      "rollback"
    ];
    commands."fast-k8s-to-tank" = {
      source = "fast/k8s";
      target = "tank/fast-backup/k8s";
      recursive = true;
      sendOptions = "w";
    };
    # Pulls, not pushed: the credential that can read brink-server's pool
    # lives here on the backup vault, not on the host being backed up
    # (hosts/nixos/brink-server/backup.nix).
    commands."brink-k8s-to-tank" = {
      source = "syncoid-remote@${config.networkConfig.hosts.brink-server.overlayIPv4}:main/k8s";
      target = "tank/brink-backup/k8s";
      recursive = true;
      sendOptions = "w";
      sshKey = config.sops.secrets."syncoid_brink_key".path;
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

  # Performance tuning via /etc/modprobe.d/ for persistence.
  #
  # ⚠️ The two ARC bounds below are the third copy on this host — see the note
  # in default.nix, including why Phase 6 left them at 8/2 GB rather than
  # spending the microVMs' freed 18 GB on ARC.
  environment.etc."modprobe.d/zfs.conf".text = ''
    options zfs zfs_arc_max=8589934592
    options zfs zfs_arc_min=2147483648
    options zfs zfs_compressed_arc_enabled=1
    options zfs l2arc_write_max=104857600
    options zfs l2arc_write_boost=209715200
  '';
}
