{ config, lib, ... }:

{
  # MicroVM TAP interfaces use the existing vmbr0 bridge
  # (configured in networking.nix)

  # Attach all vm-* TAP interfaces to the existing vmbr0 bridge
  systemd.network.networks."25-microvm-tap" = {
    matchConfig.Name = "vm-*";
    networkConfig.Bridge = "vmbr0";
    linkConfig.RequiredForOnline = "enslaved";
  };
}