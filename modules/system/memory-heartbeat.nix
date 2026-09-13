# Per-node heartbeat + memory-pressure probe, reporting to healthchecks.io.
#
# 2026-09-13. The estate already has two alerting paths — Grafana -> ntfy and
# the in-cluster dead-man's switch (homelab-k8s/monitoring/) — and ionos's
# memory-exhaustion death exposed the gap between them precisely:
#
#   * Grafana -> ntfy runs *in* the cluster on maxdata, and its node metrics
#     reach Prometheus over the overlay. Both of those died with ionos.
#   * The cluster DMS deliberately ignores single-node loss (quorum survives),
#     and needs the apiserver to run a Job at all.
#
# So a node that dies — or wedges itself the way ionos did, thrashing until
# it cannot serve TLS on loopback — is reported by nothing. This module is
# that report. It runs on the NixOS host itself and talks to healthchecks.io
# over the node's own default route, never the overlay: a third party that
# keeps working when this mesh does not, for the same reason the DMS picked
# one (see deadmans-switch.ts).
#
# Three failure shapes, three detections:
#
#   1. Node reachable and healthy        -> periodic ping to $URL (check stays Up)
#   2. Node alive, memory failing        -> ping to $URL/fail with a message
#                                           (check goes Down immediately, with
#                                           the message attached to the alert)
#   3. Node wedged so hard the timer     -> missed ping; healthchecks.io alerts
#      cannot run or the host is down       after its own grace period
#
# Case 2 needs the local probe because Grafana's view of the node (Tier 1,
# PSI rules) cannot survive the loss of maxdata/ntfy — which is exactly when
# a memory-pressured node most needs to be heard.
#
# ⚠️ The ping URL is per-host by construction: each host declares only its
# own sops secret. Leaking one URL forges one "healthy" ping — the same
# accepted trade-off deadmans-switch.ts documents for its cluster-wide URL.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.memoryHeartbeat;
  # Secret name derived from the host, not configured per host: the check is
  # 1:1 with the machine, so wiring is a single `memoryHeartbeat.enable` line
  # and the URL key in common.yaml follows the same convention. Every host
  # therefore declares and decrypts only its own URL.
  secretName = "memory_heartbeat_url_${config.hostSpec.hostName}";
  curl = "${pkgs.curl}/bin/curl";
  # PSI read straight from the kernel rather than re-derived from counters:
  # /proc/pressure/memory's avg60 is kernel-smoothed, which is what makes a
  # single reading safe to act on — a 5-second allocation burst does not
  # trip it, a sustained stall does. `full` is the same quantity the Grafana
  # rule (NodeMemoryStalled, rate of node_pressure_memory_stalled_seconds_
  # total) measures, expressed as a 60 s average percentage.
  #
  # MemAvailable/MemTotal mirrors NodeMemoryAvailableLow. Two thresholds and
  # one message either way: the receiver cares which node, not which metric.
  probe = pkgs.writeShellScript "memory-heartbeat-probe" ''
    set -eu

    url_file="$RUNTIME_DIRECTORY/ping-url"
    # A missing/empty URL must not look like health. Exit non-zero so the
    # journal records the broken state instead of silently skipping pings —
    # a silently skipped ping is indistinguishable from a healthy node and
    # defeats the third-party check entirely.
    [ -s "$url_file" ] || { echo "no ping url"; exit 1; }
    url="$(cat "$url_file")"

    stall="$(awk '/^full /{for(i=1;i<=NF;i++) if($i ~ /^avg60=/){sub("avg60=","",$i); print $i; exit}}' /proc/pressure/memory)"
    avail="$(awk '/^MemAvailable:/{a=$2}/^MemTotal:/{t=$2}END{printf "%.1f", 100-100*a/t}' /proc/meminfo)"

    msg="full-psi-avg60=''${stall:-?}% mem-used=''${avail:-?}%"
    echo "$msg"

    over_stall="$(awk -v s="''${stall:-0}" -v t="${toString cfg.psiStallPercent}" 'BEGIN{print (s+0 > t+0) ? 1 : 0}')"
    over_avail="$(awk -v a="''${avail:-0}" -v t="${toString cfg.memUsedPercent}" 'BEGIN{print (a+0 > t+0) ? 1 : 0}')"

    if [ "$over_stall" = "1" ] || [ "$over_avail" = "1" ]; then
      # /fail marks the check Down immediately; the POST body becomes the
      # alert's message on healthchecks.io. Any transient trip resolves
      # itself on the next healthy ping below.
      ${curl} -fsS -m 10 --data "$msg" "$url/fail" >/dev/null
      echo "memory pressure: pinging /fail"
    else
      ${curl} -fsS -m 10 "$url" >/dev/null
      echo "healthy: pinged"
    fi
  '';
in {
  options.memoryHeartbeat = {
    enable = lib.mkEnableOption "the per-node healthchecks.io heartbeat";

    psiStallPercent = lib.mkOption {
      type = lib.types.number;
      default = 10;
      description = ''
        Kernel PSI `full` avg60 above which the host reports failing memory,
        as a percentage. Matches the Grafana rule's 10% threshold so the two
        signal paths agree.
      '';
    };

    memUsedPercent = lib.mkOption {
      type = lib.types.number;
      default = 90;
      description = ''
        MemUsed/MemTotal (1 - MemAvailable fraction) above which the host
        reports failing memory, as a percentage. Matches
        NodeMemoryAvailableLow.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Declared unconditionally once enabled — a missing key in common.yaml
    # fails activation, which is why the URLs are added to the secrets file
    # *before* the first deploy that enables this (2026-09-13 deploy order).
    # The probe itself exits non-zero on an empty URL file rather than
    # pretending to be healthy.
    sops.secrets.${secretName} = {
      sopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
    };

    systemd.services.memory-heartbeat = {
      description = "Heartbeat + memory-pressure report to healthchecks.io";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = probe;
        RuntimeDirectory = "memory-heartbeat";
        RuntimeDirectoryMode = "0700";
        # The URL rides in the runtime directory (0600) rather than the
        # process environment, so it is readable only by the unit itself and
        # never shows up in `systemctl show` or `ps` output.
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
      preStart = ''
        install -m 0600 /run/secrets/${secretName} /run/memory-heartbeat/ping-url
      '';
    };

    systemd.timers.memory-heartbeat = {
      description = "Heartbeat to healthchecks.io every 2 minutes";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "2min";
        AccuracySec = "10s";
        # A wedged host must not silently stop pinging *this* way either —
        # that is the point of the whole module. Nothing here needs
        # Persistent=true: a missed ping during downtime is a valid report.
        Persistent = false;
      };
    };
  };
}
