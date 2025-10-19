{ config, pkgs, lib, ... }:

{
  imports = [
    (lib.custom.relativeToRoot "modules/nixos/k3s-node-template.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node2";
    nodeNumber = 2;
  };
}