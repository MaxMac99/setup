{ config, lib, ... }:

{
  # Create a bridge for microVMs to connect to the physical network
  networking.bridges."br-microvm" = {
    interfaces = [ ]; # Will add TAP interfaces dynamically
  };

  # Give the bridge an IP on the host network
  networking.interfaces."br-microvm" = {
    ipv4.addresses = [{
      address = "${config.networkConfig.staticIPs.maxdata}";
      prefixLength = 24;
    }];
  };

  # Forward traffic between bridge and physical network
  # Enable IP forwarding
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # NAT for microVMs (if needed)
  networking.nat = {
    enable = true;
    internalInterfaces = [ "br-microvm" ];
    externalInterface = "enp4s0"; # Your physical interface
  };

  # Firewall rules to allow microVM traffic
  networking.firewall.trustedInterfaces = [ "br-microvm" ];
}