{ self, config, pkgs, inputs, lib, ... }:

let
  template = import ./k3s-template.nix { inherit self config pkgs lib inputs; };
in
template.mkK3sNode {
  nodeName = "k3s-node3";
}