# Phase 11: local snapshots on main/k8s, and lets maxdata pull it over the
# overlay for an off-box copy.
#
# brink-server's local-path PVs — including Home Assistant's 857-entity
# config — sit on `main`, a single unmirrored NVMe with no point-in-time
# recovery of its own until now. Sanoid below fixes that directly, and also
# gives syncoid something better than its own bookkeeping to sync from: see
# services.syncoid.commonArgs on maxdata for why that distinction is load-
# bearing, not cosmetic — the first version of this pull left syncoid
# creating a fresh marker snapshot every run, which sanoid's target-side
# pruning can never see because it does not match sanoid's own naming, so
# the "off-box copy" quietly regrew the exact unbounded-target problem
# Phase 11 exists to fix, just under a new name.
#
# Pull rather than push, so the credential that can read this pool lives on
# the backup vault (maxdata), not on the host being backed up.
#
# No root SSH (PermitRootLogin=no, openssh.nix) and no sudo either: the
# account can do nothing beyond what `zfs allow` grants below. That is looser
# than a forced-command key would be — this user has a real shell, so an
# attacker with the private key can run anything main/k8s's delegation
# permits, not just `zfs send` — but it is also all that syncoid's SSH
# transport actually needs, and tightening it further is unverified scope
# this phase does not require.
{pkgs, ...}: {
  services.sanoid = {
    enable = true;
    datasets."main/k8s" = {
      useTemplate = ["production"];
      recursive = true;
    };
    # Matches maxdata's zfs.nix production template exactly, so the two
    # halves of the estate's backup posture read as one policy, not two.
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

  users.users.syncoid-remote = {
    isSystemUser = true;
    group = "syncoid-remote";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLFoMRejWSZa3wNRMhKxefHMNmBWShpNkmm8UiZe1/d syncoid-remote@maxdata"
    ];
  };
  users.groups.syncoid-remote = {};

  # zfs allow persists in the pool's dataset properties, not in system state,
  # so this only needs to actually run once — but it is idempotent and cheap,
  # and re-asserting on every boot means a `zfs allow` that was ever cleared
  # by hand (or by a `zfs recv` of a raw send, which can reset permissions)
  # self-heals rather than failing the next syncoid pull silently.
  #
  # Mirrors services.syncoid's own localSourceAllow default set (syncoid.nix
  # upstream) so this remote user can do exactly what a local syncoid source
  # user could.
  systemd.services.syncoid-remote-allow = {
    description = "Delegate zfs send permissions on main/k8s to syncoid-remote";
    after = ["zfs.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # The booted system's zfs, not this generation's — same reasoning as
      # the sanoid/syncoid modules upstream: it guarantees the stable API
      # ZFS needs rather than whatever this activation happens to carry.
      ExecStart = "/run/booted-system/sw/bin/zfs allow syncoid-remote bookmark,hold,send,snapshot,destroy,mount main/k8s";
    };
  };
}
