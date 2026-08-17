# Phase 12: ZFS and smartctl exporters. Node metrics are deliberately *not*
# added here — homelab-k8s already runs `prometheus-prometheus-node-exporter`
# as a hostNetwork DaemonSet on every node except maxdata (its nodeAffinity
# explicitly excludes it by hostname, because maxdata is the one host that
# predates the DaemonSet and already ran its own). Adding a host-level one
# here fights that pod for :9100 — confirmed live on 2026-08-15: the DaemonSet
# pod already owned the port and the systemd unit crash-looped
# ("address already in use") until this was reverted to just ZFS/smartctl.
{
  config,
  inputs,
  ...
}: {
  imports = [inputs.zfs-exporter.nixosModules.default];

  services.zfs-prometheus-exporter = {
    enable = true;
    port = 9134;
    logLevel = "debug";
    logFormat = "json";
  };

  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9116;
  };

  # ⚠️ Deliberately not `openFirewall`/`trustedInterfaces` here: eno1 already
  # trusts everything (Music Assistant, see default.nix), so any port opened
  # by these exporters is already reachable from the Brink LAN regardless of
  # what this file does. Opened explicitly on the overlay interface too,
  # because that's how an in-cluster Prometheus actually reaches this host —
  # via its Kubernetes `INTERNAL-IP`, which D3 puts on `tailscale0` — and that
  # path must not depend on the LAN trust surviving the Phase 12 cleanup item
  # tracked in the decision log.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [9116 9134];
}
