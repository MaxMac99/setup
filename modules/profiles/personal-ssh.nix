# Personal SSH configuration profile — Macs only.
#
# The private keys live in 1Password and ssh reaches them through its agent
# (modules/profiles/projects.nix owns the `Host *` block and the IdentityAgent
# setting). `IdentitiesOnly yes` still needs a file to decide *which*
# agent-resident key to offer, so the public halves are referenced straight out
# of the Nix store: immutable, root-owned, and nothing lands in ~/.ssh that can
# be mistaken for a stray key copy and deleted.
{config, ...}: let
  # max's interactive admin key. It is both inbound and outbound — installed
  # into authorized_keys on every host by modules/system/base.nix, and presented
  # from here — so it lives in ../data/keys and is referenced, never copied. It
  # belongs to the person, not to a machine: the private half is in 1Password,
  # so any device with the vault can use it. Machine-to-machine keys such as
  # modules/data/keys/maxdata.pub stay device-bound and keep their hostname,
  # because a headless host cannot talk to a vault agent.
  adminKey = "${../data/keys/max-admin.pub}";

  # Outbound only — see ../data/pubkeys/README.md for why this must not live in
  # ../data/keys, which base.nix grants login with on every host.
  hetznerKey = "${../data/pubkeys/id_hetzner.pub}";
in {
  home-manager.users.${config.hostSpec.username} = {lib, ...}: {
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
        # At Winkel on its static address since 2026-08-06. Do not use
        # mDNS: maxdata's Avahi still serves a stale k3s-pi.local record for
        # the DHCP address this host used to hold under its old name.
        "winkel-pi" = lib.hm.dag.entryAfter ["*"] {
          HostName = "192.168.178.3";
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
