{ lib, ... }:

{
  imports = [
    (lib.custom.relativeToRoot "modules/nixos/k3s-node-shared.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node1";
    nodeNumber = 1;
    isFirstNode = true;
  };
}