{ lib, ... }:

let
  template = import (lib.custom.relativeToRoot "modules/nixos/k3s-node-template.nix") { inherit lib; };
in
template.mkK3sNode {
  nodeName = "k3s-node2";
  nodeNumber = 2;
}