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
  };
}