{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Address plan lives in modules/data/network-config.nix, not inline here, so
  # the router's static route and this host cannot drift apart.
  site = config.networkConfig.sites.winkel;
  self = config.networkConfig.hosts.k3s-pi;
  prefixLength = lib.toInt (lib.last (lib.splitString "/" site.subnet));
in {
  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/system/minimal-zsh.nix"
    ])
    # Board specifics only. `nixos-raspberrypi.lib.nixosSystem` (see flake.nix)
    # already supplies inject-overlays, nixpkgs-rpi and trusted-nix-caches —
    # importing inject-overlays a second time applies the kernel/firmware
    # overlay twice and evaluation recurses inside `raspberrypiWirelessFirmware`.
    ++ (with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-4.base
    ])
    ++ [./hardware-configuration.nix];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Pi PoE+ HAT: enable the rpi-poe-plus DT overlay so the EMC2301 fan
  # controller and temperature-based fan curve work.
  hardware.raspberry-pi.config.all.dt-overlays.rpi-poe-plus = {
    enable = true;
    params = {};
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  hostSpec = {
    username = "max";
    hostName = "k3s-pi";
    isMinimal = true;
  };

  networking = {
    hostName = "k3s-pi";
    hostId = "03030303";

    # Static, because the FritzBox static route for 192.168.1.0/24 points here
    # (Phase 3) and a subnet router cannot sit on a lease. `.3` is outside the
    # FritzBox DHCP pool (.20–.200) and was verified free from the Winkel LAN
    # itself — no ping response, no ARP entry — on 2026-08-06.
    #
    # IPv4 only: `useDHCP = false` stops the DHCPv4 client, while IPv6 keeps
    # arriving by RA/SLAAC as before. Nothing here depends on the site's IPv6
    # prefix, which D2 forbids relying on.
    useDHCP = false;
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = self.lanIPv4;
          inherit prefixLength;
        }
      ];
    };
    defaultGateway = site.gateway;
    nameservers = site.dnsServers;

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
    };
  };

  # IPv6 keeps arriving by SLAAC now that dhcpcd is gone — the kernel does it.
  # `accept_ra = 2` rather than the default 1 because a host ignores RAs when
  # forwarding is on, and this box becomes a subnet router in Phase 3.
  #
  # Beware when switching a *running* host off DHCP: dhcpcd leaves
  # `addr_gen_mode=1` (none), `autoconf=0` and `accept_ra=0` behind on its
  # interface, so IPv6 vanishes entirely — no global address and not even a
  # link-local — until those are reset or the host reboots. A clean boot
  # restores the kernel defaults, so this only bites during a live switch.
  boot.kernel.sysctl."net.ipv6.conf.end0.accept_ra" = 2;

  # Self-update path. The pi clones and pulls this repo itself from GitHub over
  # SSH, so it no longer depends on anyone copying a tree onto it. Its private
  # key is placed out-of-band at /home/max/.ssh/id_k3s_pi — a headless host
  # cannot reach a vault agent, so this is a device key like maxdata's — and the
  # public half is registered as a *read-only* deploy key scoped to this one
  # repo, so a compromised pi cannot rewrite the fleet's configuration.
  programs.ssh.extraConfig = ''
    Host github.com
      User git
      IdentitiesOnly yes
      IdentityFile /home/max/.ssh/id_k3s_pi
  '';

  # /etc/nixos is owned by max, so `git pull` uses max's deploy key and root
  # never needs an SSH identity. nixos-rebuild still evaluates as root, and
  # libgit2 refuses to open a repository it does not own without this.
  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };

  # mDNS so the host is reachable as k3s-pi.local without a static lease.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Home Assistant and matter-server were removed here (migration Phase 5.2
  # item 4): they move to brink-server, which sits on the Brink segment where
  # every smart-home device actually lives. Once the pi moved to Winkel they
  # could not reach a single device anyway — there is no cross-site mDNS — so
  # this only stops building a large Python stack on a Pi 4 for nothing.
  #
  # /var/lib/hass (313 M) was backed up first, to
  # ~/backup/pre-multi-site/pi-hass-2026-08-05.tar.gz. The state directory is
  # left on disk; NixOS does not delete it when the service is removed.

  system.stateVersion = "25.11";
}
