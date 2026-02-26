{lib, ...}: {
  imports = [
    (lib.custom.relativeToRoot "modules/system/k3s-node.nix")
  ];

  k3sNode = {
    nodeName = "k3s-node2";
    nodeNumber = 2;
  };
}