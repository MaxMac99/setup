# Personal SSH configuration profile — Macs only.
#
# The private keys live in 1Password and ssh reaches them through its agent
# (modules/profiles/projects.nix owns the `Host *` block and the IdentityAgent
# setting). What lands on disk is only the public half, under ~/.ssh/1password/
# so it cannot collide with an unmanaged ~/.ssh/id_*.pub.
{config, ...}: let
  pubKeyDir = ".ssh/1password";

  # max's interactive admin key: committed as modules/data/keys/max-admin.pub and
  # installed into authorized_keys on every host by modules/system/base.nix. It
  # belongs to the person, not to a machine — the private half is in 1Password,
  # so any device with the vault can use it. Machine-to-machine keys such as
  # modules/data/keys/maxdata.pub stay device-bound and keep their hostname,
  # because a headless host cannot talk to a vault agent.
  adminKey = "~/${pubKeyDir}/id_max_admin.pub";
  hetznerKey = "~/${pubKeyDir}/id_hetzner.pub";
in {
  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
    home.file = {
      "${pubKeyDir}/id_max_admin.pub".source = ../data/keys/max-admin.pub;
      "${pubKeyDir}/id_hetzner.pub".text = ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKA8xBELyk1Lh4TYvFEGBCyymas7TlZRyohCNwhm9ioS id_hetzner
      '';
    };

    programs.ssh = {
      settings = {
        "ionos" = lib.hm.dag.entryAfter ["*"] {
          HostName = "212.132.82.102";
          User = "max";
          IdentityFile = adminKey;
        };
        "maxdata" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.2";
          User = "max";
          IdentityFile = adminKey;
        };
        # Still physically at Brink on a DHCP lease; moves to 192.168.178.3 in
        # Phase 5. Do not use k3s-pi.local — maxdata's Avahi still serves a stale
        # record for 192.168.178.118 from when the pi last lived at Winkel.
        "k3s-pi" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.1.90";
          User = "max";
          IdentityFile = adminKey;
        };
        # The three microVMs are decommissioned in Phase 6; these go with them.
        "k3s-node1" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.5";
          User = "max";
          IdentityFile = adminKey;
        };
        "k3s-node2" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.6";
          User = "max";
          IdentityFile = adminKey;
        };
        "k3s-node3" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.7";
          User = "max";
          IdentityFile = adminKey;
        };
        "hetzner" = lib.hm.dag.entryAfter ["*"] {
          HostName = "u499100.your-storagebox.de";
          User = "u499100";
          Port = 23;
          IdentitiesOnly = true;
          IdentityFile = hetznerKey;
        };
      };
    };
  };
}
