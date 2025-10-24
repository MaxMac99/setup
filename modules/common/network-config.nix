# Global Network Configuration
{
  lib,
  ...
}: {
  options.networkConfig = {
    dns = {
      primary = lib.mkOption {
        type = lib.types.str;
        default = "192.168.178.1";
        description = "Primary DNS server (FritzBox)";
      };
      servers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "192.168.178.1" "1.1.1.1" ];
        description = "List of DNS servers";
      };
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "192.168.178.1";
      description = "Default gateway";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "192.168.178.0/24";
      description = "Local subnet";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "local";
      description = "Local domain name";
    };

    staticIPs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        maxdata = "192.168.178.2";
        k3s-node1 = "192.168.178.5";
        k3s-node2 = "192.168.178.6";
        k3s-node3 = "192.168.178.7";
      };
      description = "Static IP assignments for hosts";
    };

    staticIPv6s = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # Private ULA addresses - NOT exposed to internet
        # Only accessible via local network or WireGuard tunnel
        maxdata = "fda8:a1db:5685::2";
        k3s-node1 = "fda8:a1db:5685::5";
        k3s-node2 = "fda8:a1db:5685::6";
        k3s-node3 = "fda8:a1db:5685::7";
      };
      description = "Static IPv6 assignments (private ULA - not internet routable)";
    };

    ipv6Gateway = lib.mkOption {
      type = lib.types.str;
      default = "fda8:a1db:5685::1";
      description = "IPv6 gateway (local)";
    };
  };
}