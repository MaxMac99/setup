let
  lib = (import <nixpkgs> {}).lib;
  template = import ../../modules/nixos/k3s-node-template.nix { inherit lib; };
in
template.mkK3sNode {
  nodeName = "k3s-node1";
  nodeNumber = 1;
  isFirstNode = true;
}