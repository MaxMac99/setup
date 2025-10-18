/**
 * Shared configuration for Proxmox infrastructure
 *
 * This configuration should match the values in:
 * - modules/common/network-config.nix
 * - hosts/nixos/pi/configuration.nix (dnsmasq static leases)
 */

export const NetworkConfig = {
  dns: {
    primary: "192.168.178.1" as const, // FritzBox
    servers: ["192.168.178.1"],
  },
  gateway: "192.168.178.1" as const,
  subnet: "192.168.178.0/24" as const,
  domain: "local" as const,

  // Static IP assignments
  staticIPs: {
    maxdata: "192.168.178.2",
    "k3s-node1": "192.168.178.11",
    "k3s-node2": "192.168.178.12",
    "k3s-node3": "192.168.178.13",
  } as const,
};

export const ProxmoxConfig = {
  nodeName: "maxdata" as const,
  datastoreId: "fast" as const,
};