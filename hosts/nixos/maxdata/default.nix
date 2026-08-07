{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/profiles/core-user"
      "modules/profiles/development.nix"
      "modules/profiles/gcloud.nix"
      "modules/profiles/full-nvim.nix"
      "modules/system/overlay-client.nix"
      "modules/system/k3s-cluster.nix"
    ])
    ++ [
      inputs.zfs-exporter.nixosModules.default
      ./networking.nix
      ./zfs.nix
      ./smb.nix
      ./monitoring.nix
      ./hardware-configuration.nix
    ];

  hostSpec = {
    username = "max";
    hostName = "maxdata";
  };

  # Joins the mesh as a peer but advertises no subnet — the pi is Winkel's
  # subnet router (3.1). maxdata still needs the overlay itself, because from
  # Phase 7 its k3s --node-ip is an overlay address (D3).
  overlayClient = {
    enable = true;
    authKeySecret = "overlay_authkey";
  };

  # k3s server at Winkel (Phase 7) — the role the three microVMs used to fill
  # between them, now run natively on the host that already owns the storage.
  # That is the point of Phase 6: the ZFS pools, the NFS exports and the k3s
  # server are finally the same machine, with no virtiofs in between.
  k3sCluster.enable = true;

  # maxdata's first sops block. It was a declared recipient of both files since
  # before Phase 0 while consuming nothing, which is the drift Phase 0.5 spotted
  # and 2b.3 item 1 carried.
  #
  # Straight to a **host** key (D11/2b.2) rather than the user key its original
  # recipient came from. That shortcut is available here precisely *because*
  # nothing consumed sops on this host: there is no running service to migrate,
  # so there is no transition to stage — unlike ionos, where a live k3s_token
  # forced the additive dance.
  #
  # ⚠️ Phase 6.1 calls this the single highest-risk item in the migration: the
  # microVMs' k3s token is encrypted to identities that live *inside* the disk
  # images that phase deletes, so if maxdata cannot decrypt k3s.yaml first, the
  # token is gone. Proven before this was written, not after — an actual
  # `sops -d` on the box under an age key derived from
  # /etc/ssh/ssh_host_ed25519_key reproduced both plaintext hashes exactly. The
  # old user-key recipient is deliberately still in .sops.yaml as a fallback.
  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
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
      forceImportRoot = false;
    };

    # ZFS ARC tuning for 32 GB RAM.
    #
    # The old comment here read "18GB reserved for 3x 6GB microVMs". Phase 6
    # destroyed those guests, so nothing is reserved for them any more — but
    # the 8 GB cap deliberately did **not** move with them.
    #
    # The freed 18 GB was a *fixed* reservation backing workloads that ran
    # inside the guests, and those same workloads come back as native pods on
    # this host from Phase 7. Giving the memory to ARC would only mean
    # reclaiming it under pressure later, and ARC gives ground grudgingly. So
    # it stays as k3s headroom instead: 8 GB ARC, ~23 GB for the OS, k3s and
    # what it schedules.
    #
    # ⚠️ zfs_arc_max is set in three places on this host and they must agree —
    # here as a kernelParam, here again as modprobe options, and a third time
    # in zfs.nix's environment.etc."modprobe.d/zfs.conf".
    kernelParams = [
      "zfs.zfs_arc_max=8589934592" # 8GB ARC max
      "zfs.zfs_arc_min=2147483648" # 2GB ARC min
    ];
    extraModprobeConfig = ''
      options zfs zfs_arc_max=8589934592
      options zfs zfs_arc_min=2147483648
    '';
  };

  # CRITICAL: Required for ZFS
  networking.hostId = "ec7b6b2d";

  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
  };

  # NFS server for K3s persistent volumes
  services.nfs.server = {
    enable = true;
    exports = ''
      /tank/k8s/nfs 192.168.178.0/24(rw,sync,no_subtree_check,no_root_squash)
      /tank/k8s/timemachine 192.168.178.0/24(rw,async,no_subtree_check,no_root_squash)
    '';
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
    startWhenNeeded = false; # Always start, don't wait for socket activation
  };

  # Keep SSH running even in emergency/rescue mode
  systemd.services.sshd = {
    unitConfig = {
      IgnoreOnIsolate = true; # Don't stop SSH when switching to emergency mode
    };
    wantedBy = lib.mkForce ["multi-user.target" "emergency.target" "rescue.target"];
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

  system.stateVersion = "24.11";
}
