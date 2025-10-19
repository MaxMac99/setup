{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.microvm.nixosModules.microvm
    (lib.custom.relativeToRoot "modules/common/host-spec.nix")
    (lib.custom.relativeToRoot "modules/common/network-config.nix")
    (lib.custom.relativeToRoot "modules/nixos/k3s-node-template.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node3";
    nodeNumber = 3;
  };
}