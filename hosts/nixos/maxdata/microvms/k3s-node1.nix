{ config, pkgs, inputs, lib, ... }:

let
  template = import ./k3s-template.nix { inherit config pkgs lib; };
in
template.mkK3sNode {
  nodeName = "k3s-node1";
  nodeNumber = 1;
  isFirstNode = true;
}