# Phase 12: node, ZFS and smartctl exporters, mirroring maxdata's
# hosts/nixos/maxdata/monitoring.nix. Brink has one host, so nothing here
# is per-node parameterised the way a shared module would need to be.
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

  # ⚠️ Deliberately not `openFirewall`/`trustedInterfaces` here: eno1 already
  # trusts everything (Music Assistant, see default.nix), so any port opened
  # by these exporters is already reachable from the Brink LAN regardless of
  # what this file does. Opened explicitly on the overlay interface too,
  # because that's how an in-cluster Prometheus actually reaches this host —
  # via its Kubernetes `INTERNAL-IP`, which D3 puts on `tailscale0` — and that
  # path must not depend on the LAN trust surviving the Phase 12 cleanup item
  # tracked in the decision log.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [9100 9116 9134];
}
