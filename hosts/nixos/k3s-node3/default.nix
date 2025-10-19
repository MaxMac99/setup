{ lib, ... }:

let
  template = import ../../../modules/nixos/k3s-node-template.nix { inherit lib; };
in
template.mkK3sNode {
  nodeName = "k3s-node3";
  nodeNumber = 3;
}