# Phase 12: smartctl exporter only. No ZFS here (winkel-pi has no pool, see
# hardware-configuration.nix), and node metrics are deliberately *not* added —
# homelab-k8s already runs `prometheus-prometheus-node-exporter` as a
# hostNetwork DaemonSet on every node except maxdata (excluded by an explicit
# nodeAffinity, because maxdata predates the DaemonSet and runs its own). A
# host-level one here would fight that pod for :9100, exactly as it did on
# brink-server on 2026-08-15 — see that host's monitoring.nix.
#
# smartctl is worth it specifically on this host — its root disk sits behind
# the ASM1153 USB-SATA bridge that hardware-configuration.nix already
# documents as having dropped under sustained write load once.
{config, ...}: {
  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9116;
  };

  # winkel-pi's own firewall only allows 22 (default.nix). smartctl is opened
  # on the overlay interface only, the same reasoning as
  # brink-server/monitoring.nix: an in-cluster Prometheus reaches this host at
  # its Kubernetes `INTERNAL-IP`, which is the `tailscale0` address.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [9116];
}
