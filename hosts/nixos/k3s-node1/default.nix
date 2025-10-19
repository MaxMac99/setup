{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.microvm.nixosModules.microvm
    (lib.custom.relativeToRoot "modules/nixos/k3s-node-template.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node1";
    nodeNumber = 1;
    isFirstNode = true;
  };
}