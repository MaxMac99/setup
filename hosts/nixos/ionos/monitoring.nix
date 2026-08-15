# Phase 12: node exporter only. No ZFS (this host is ext4 on a single virtio
# disk, hardware-configuration.nix), and no smartctl — virtio-blk does not
# expose SMART data to the guest, so the exporter would just report nothing.
{config, ...}: {
  services.prometheus.exporters.node = {
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

  # ⚠️ Must land on the overlay interface only, never on ionos's global
  # `allowedTCPPorts` (default.nix) — that list also covers the public `ens6`
  # NIC, and this host has already lost sshd/k3s/nginx/Headscale once from a
  # config change that looked unrelated to any of them (see CLAUDE.md). An
  # in-cluster Prometheus reaches ionos at its Kubernetes `INTERNAL-IP`,
  # which D3 puts on `tailscale0`.
  networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [9100];
}
