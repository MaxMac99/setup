{ self, config, pkgs, lib, inputs, ... }:

{
  # Template function to create k3s microvm declarations
  # Usage: mkK3sNode { nodeName = "k3s-node1"; }
  #
  # This creates a minimal VM declaration that references the nixosConfiguration.
  # All VM hardware settings (hypervisor, vcpu, mem, etc.) are defined in the
  # nixosConfiguration itself (modules/nixos/k3s-node-template.nix).
  mkK3sNode = { nodeName, ... }:
    {
      microvm.vms.${nodeName} = {
        # Reference the flake's nixosConfiguration for this node
        # The VM will use nixosConfigurations.${nodeName} from the flake
        flake = self;

        # Optional: Allow updating the VM's flake reference imperatively
        # updateFlake = "git+file:///etc/nixos";
      };
    };
}