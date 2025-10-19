{ lib, ... }:

{
  imports = [
    (lib.custom.relativeToRoot "modules/nixos/k3s-node-shared.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node3";
    nodeNumber = 3;
  };
}