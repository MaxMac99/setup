# Personal SSH configuration profile
{config, ...}: {
  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          AddKeysToAgent = "yes";
        };
        "kopf3.github.com" = lib.hm.dag.entryAfter ["*"] {
          HostName = "github.com";
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_kopf3_github";
        };
        "github.com" = lib.hm.dag.entryAfter ["kopf3.github.com"] {
          HostName = "github.com";
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_github";
        };
        "ionos" = lib.hm.dag.entryAfter ["*"] {
          HostName = "212.132.82.102";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "borkenpi4" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.118";
          User = "pi";
          IdentityFile = "~/.ssh/id_borkenpi4";
        };
        "maxdata" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.2";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "k3s-pi" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.3";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "k3s-node1" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.5";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "k3s-node2" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.6";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "k3s-node3" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.7";
          User = "max";
          IdentityFile = "~/.ssh/id_ionos_vps";
        };
        "hetzner" = lib.hm.dag.entryAfter ["*"] {
          HostName = "u499100.your-storagebox.de";
          User = "u499100";
          Port = 23;
          IdentitiesOnly = true;
          IdentityFile = "~/.ssh/id_hetzner";
        };
      };
    };
  };
}
