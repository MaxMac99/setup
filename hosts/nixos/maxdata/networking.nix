{
  config,
  lib,
  pkgs,
  ...
}: let
  site = config.networkConfig.sites.winkel;
  self = config.networkConfig.hosts.maxdata;
in {
  # Enable networking
  networking.networkmanager.enable = false; # We use systemd-networkd for servers
  networking.useDHCP = false; # Disable default DHCP since we use systemd-networkd
  networking.useNetworkd = true; # Use systemd-networkd

  # Use systemd-networkd for consistent network configuration
  systemd.network.enable = true;

  # vmbr0 — a Proxmox-era name for what is now simply maxdata's LAN interface.
  #
  # ⚠️ Phase 6 deliberately did *not* rename it. The netdev is what every
  # address on this host rides on, and re-creating a netdev is precisely what
  # drops those addresses during a networkd reload (6.5). Renaming buys nothing
  # but cosmetics and costs the one failure mode this phase has to avoid, on a
  # host whose console nobody is sitting at. Left for a phase that is not also
  # doing something irreversible.
  systemd.network.netdevs."20-vmbr0" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "vmbr0";
    };
  };

  # Bind physical interface to bridge (no IP on physical interface)
  systemd.network.networks."20-vmbr0-bind" = {
    matchConfig.Name = "enp*";
    networkConfig.Bridge = "vmbr0";
    linkConfig.RequiredForOnline = "enslaved";
  };

  systemd.network.networks."30-vmbr0" = {
    matchConfig.Name = "vmbr0";
    networkConfig = {
      Address = "${self.lanIPv4}/24";
      Gateway = site.gateway;
      # Winkel's own resolver first (winkel-pi), the FritzBox second.
      #
      # Until Phase 6 this read networkConfig.dns.servers — the deprecated
      # single-site list of [FritzBox, 1.1.1.1] — which made maxdata the only
      # host at either site not resolving through its own site resolver, and
      # the only one that could still reach a public resolver directly. Phase 4
      # put both sites on local AdGuard; this is maxdata catching up.
      DNS = site.dnsServers;
      IPv6AcceptRA = true;
    };
  };

  # ⚠️ systemd-resolved picks a DNS server once and never re-elects.
  #
  # Measured on this host, 2026-08-06 (Phase 6):
  #
  #   23:02:29.290  resolved: switching to fallback DNS server 1.1.1.1
  #   23:02:30.221  networkd: Configuring vmbr0 (the DNS list above lands here)
  #   23:02:33.391  networkd: vmbr0 gained carrier      <- 3.2 s later
  #
  # resolved is handed the server list 3.2 s before the link can carry a
  # packet. Its first query to winkel-pi cannot be answered, so it rotates to
  # the second entry — the FritzBox — and stays there for the life of the boot.
  # A 60 s idle period and six varied queries confirmed it never rotates back.
  #
  # The failure is silent and total in effect: the FritzBox answers everything
  # perfectly well, so the host looks healthy while `doubleclick.net` resolves
  # to a real address and `*.mvissing.de` resolves to the dead public ingress
  # instead of the site VIP. Both blocking and split-horizon are bypassed, and
  # nothing logs a complaint.
  #
  # Restarting resolved once the link is genuinely up re-elects the head of the
  # list, and it then stays on winkel-pi indefinitely. network-online.target is
  # the right trigger: it was reached at 23:02:35.338, two seconds after
  # carrier, on the same boot.
  #
  # maxdata is the only host this can affect — brink-server and winkel-pi *are*
  # their sites' resolvers and point at themselves, so their primary is up as
  # soon as their link is.
  systemd.services.resolved-reelect-primary = {
    description = "Re-elect the primary DNS server once the link is really up";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "systemd-resolved.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart systemd-resolved.service";
    };
  };

  networking.firewall = {
    enable = true;
    # Phase 6 dropped four Proxmox-era ports that nothing has served since this
    # machine stopped being a Proxmox host: 8006 (Proxmox UI), 9090 (Cockpit),
    # 5900 (VNC for VM consoles) and 3128 (subscription proxy).
    allowedTCPPorts = [
      22 # SSH
      111 # NFS portmapper
      2049 # NFS
    ];
    allowedUDPPorts = [
      111 # NFS portmapper
      2049 # NFS
    ];

    # ⚠️ This trusts the whole LAN, not just the VMs the comment used to claim.
    # vmbr0 is maxdata's only LAN interface, so this rule is the *first* one in
    # nixos-fw and the port list above is largely cosmetic.
    #
    # Phase 6 deliberately kept it. Removing it makes the firewall real for the
    # first time, and two things depend on it that the list does not cover:
    # node_exporter (9100) and smartctl_exporter (9116) are opened by nothing
    # else, and rpc.mountd/statd hold dynamic ports unless pinned. Neither can
    # be tested this phase — the cluster that scrapes the exporters and mounts
    # the exports is destroyed here and not rebuilt until Phase 7. Phase 8
    # wires NFS up against a real consumer and is where this comes out, with
    # the exporter ports opened explicitly and the NFS ports pinned.
    trustedInterfaces = ["vmbr0"];
  };

  # Enable avahi for mDNS (optional - for .local domain)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      workstation = true;
    };
  };

  # Hostname resolution — maxdata's own name must resolve to its LAN address
  # rather than to loopback, because Samba and the NFS exports advertise it.
  networking.extraHosts = ''
    ${self.lanIPv4} maxdata.${config.networkConfig.domain} maxdata
  '';
}
