{ self, config, pkgs, inputs, lib, ... }:

{
  imports = [
    inputs.microvm.nixosModules.host
    ./microvms/k3s-node1.nix
    ./microvms/k3s-node2.nix
    ./microvms/k3s-node3.nix
  ];

  # Enable microvm host
  microvm.host.enable = true;

  # Autostart microVMs on boot
  microvm.autostart = [
    "k3s-node1"
    "k3s-node2"
    "k3s-node3"
  ];

  # Make microvm services restart on configuration changes
  systemd.services = {
    "microvm@k3s-node1".restartIfChanged = true;
    "microvm@k3s-node2".restartIfChanged = true;
    "microvm@k3s-node3".restartIfChanged = true;
  };
}
