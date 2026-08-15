# Phase 12: node and smartctl exporters. No ZFS here (winkel-pi has no pool,
# see hardware-configuration.nix), but smartctl is worth it specifically on
# this host — its root disk sits behind the ASM1153 USB-SATA bridge that
# hardware-configuration.nix already documents as having dropped under
# sustained write load once.
{config, ...}: {
  services.prometheus.exporters = {
    node = {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"
        "filesystem"
        "diskstats"
        "processes"
        "interrupts"
      ];
    };
    smartctl = {
      enable = true;
      port = 9116;
    };
  };

  # winkel-pi's own firewall only allows 22 (default.nix). Node/smartctl are
  # opened on the overlay interface only, the same reasoning as
  # brink-server/monitoring.nix: an in-cluster Prometheus reaches this host at
  # its Kubernetes `INTERNAL-IP`, which is the `tailscale0` address.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [9100 9116];
}
