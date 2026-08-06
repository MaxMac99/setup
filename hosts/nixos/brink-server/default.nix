{
  config,
  lib,
  pkgs,
  ...
}: let
  # Address plan lives in modules/data/network-config.nix, not inline here, so
  # the UDM SE's static route (Phase 3) and this host cannot drift apart.
  site = config.networkConfig.sites.brink;
  self = config.networkConfig.hosts.brink-server;
  # The string form ("24"), because systemd-networkd's Address= wants CIDR.
  prefix = lib.last (lib.splitString "/" site.subnet);
in {
  imports =
    (map lib.custom.relativeToRoot [
      "modules/system/openssh.nix"
      "modules/system/minimal-zsh.nix"
      "modules/system/overlay-client.nix"
      "modules/system/site-dns.nix"
    ])
    ++ [./hardware-configuration.nix];

  hostSpec = {
    username = "max";
    hostName = "brink-server";
    isMinimal = true;
  };

  # Brink's subnet router (networkConfig.hosts.brink-server.subnetRouter). It
  # advertises 192.168.1.0/24 and is the next hop for the UDM SE's static route
  # to Winkel. Brink has no second always-on host, so this is a single point of
  # failure for cross-site routing here — accepted in 3.2 because the UDM SE
  # cannot fill the role itself.
  overlayClient = {
    enable = true;
    authKeySecret = "overlay_authkey";
  };

  # Brink's DNS resolver (networkConfig.sites.brink.adguard = this host's own
  # .2). ⚠️ brink-server is Brink's only always-on machine, so this is a single
  # point of failure for the site's ad-blocking — accepted in Phase 4, not
  # designed around. The UDM SE is handed out as secondary resolver, and
  # clients pick between the two nondeterministically, so an outage here makes
  # blocking leaky rather than cleanly absent.
  siteDns.enable = true;

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    # Stable kernel rather than latest, matching maxdata: ZFS trails new kernel
    # releases, and root-on-ZFS turns "module does not build" into "host does
    # not boot".
    kernelPackages = pkgs.linuxPackages;

    supportedFilesystems = ["zfs"];
    zfs = {
      devNodes = "/dev/disk/by-id";
      forceImportRoot = false;
    };

    # 32 GB RAM with nothing reserved — unlike maxdata, which holds 18 GB back
    # for microVMs until Phase 6. 8 GiB of ARC leaves ample room for the Phase 8
    # workloads that land here (Home Assistant, Mosquitto).
    #
    # Both places must agree; maxdata has the same value duplicated three times
    # and Phase 6.3 has to chase all of them.
    kernelParams = [
      "zfs.zfs_arc_max=8589934592" # 8 GiB
      "zfs.zfs_arc_min=1073741824" # 1 GiB
    ];
    extraModprobeConfig = ''
      options zfs zfs_arc_max=8589934592
      options zfs zfs_arc_min=1073741824
    '';
  };

  # Required by ZFS. Random, and distinct from maxdata's ec7b6b2d and the pi's
  # 03030303 — the pi's collides in form with the old node3 and is renamed in
  # Phase 5.2, so do not copy that pattern.
  networking.hostId = "b21961a5";

  console = {
    font = "Lat2-Terminus16";
    keyMap = "de";
  };

  networking = {
    # systemd-networkd, not scripted networking. This is a deliberate departure
    # from the pi: on a scripted-networking host `nixos-rebuild test/switch`
    # stops dhcpcd — which drops every address and route — without starting
    # network-setup.service, so the interface is left bare. That cost two
    # recoveries on the pi (migration doc 6.5). A subnet router is exactly the
    # host you cannot afford to lose that way.
    useDHCP = false;
    useNetworkd = true;

    firewall = {
      enable = true;
      # Phase 3 added the overlay; Phase 4 adds 53 and the AdGuard UI from
      # modules/system/site-dns.nix, which merges into these lists rather than
      # replacing them. Phase 7 adds k3s.
      allowedTCPPorts = [22];
    };
  };

  systemd.network = {
    enable = true;
    networks."10-lan" = {
      # The M70q's single onboard NIC, read off the hardware 2026-08-06:
      # eno1, MAC 84:a9:38:4c:9a:71, altnames enp0s31f6 / enx84a9384c9a71.
      # Pinned by name rather than left as `en*`, which would also claim a USB
      # NIC — not something to leave loose on the host that becomes Brink's
      # subnet router. Name rather than MAC, so a board swap does not silently
      # leave the box with no address.
      matchConfig.Name = "eno1";
      networkConfig = {
        # Static, because the UDM SE's static route for 192.168.178.0/24 points
        # here (Phase 3) and a subnet router cannot sit on a lease. `.2` is
        # below the UDM SE's DHCP floor of `.6` and was verified free in
        # Phase 0.
        Address = "${self.lanIPv4}/${prefix}";
        Gateway = site.gateway;
        DNS = site.dnsServers;
        # networkd does its own RA handling, so unlike the pi this needs no
        # net.ipv6.conf.*.accept_ra=2 sysctl to keep working once Phase 3 turns
        # on forwarding.
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # mDNS, so the box answers as brink-server.local before DNS exists — and,
  # from Phase 8, so Home Assistant can discover the Brink segment's devices.
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

  # Host key, not a user key (D11, 2b.2) — ionos and maxdata both derive from a
  # *user* key today and both are scheduled to be corrected.
  #
  # No secrets are declared yet, and that is what makes this safe to commit
  # before the host exists: brink-server needs none until the overlay pre-auth
  # key (Phase 3) and the k3s token (Phase 7). sops-nix with an empty secret set
  # is a no-op at activation, so the first boot cannot fail on a key that has
  # not been enrolled in .sops.yaml — which is impossible until the key exists.
  sops = {
    defaultSopsFile = lib.custom.relativeToRoot "secrets/common.yaml";
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  };

  # Self-update from GitHub, mirroring the pi (migration doc 5.2). Here it is
  # more than convenience: both Macs are aarch64-darwin and cannot build
  # x86_64-linux, so `nixos-rebuild --flake .#brink-server` from a laptop has no
  # way to produce a closure without a remote builder. The box builds its own,
  # and `git pull && nixos-rebuild switch` runs here.
  #
  # The key is a *device* key at /home/max/.ssh/id_brink_server, placed
  # out-of-band — a headless host cannot reach a vault agent, which is also why
  # host age identities can never come from 1Password (2b.1). Its public half is
  # a **read-only** deploy key scoped to this one repo, so a compromised
  # brink-server cannot rewrite the fleet's configuration. It must be a distinct
  # key from the pi's: GitHub rejects the same deploy key twice.
  programs.ssh.extraConfig = ''
    Host github.com
      User git
      IdentitiesOnly yes
      IdentityFile /home/max/.ssh/id_brink_server
  '';

  # /etc/nixos is owned by max, so `git pull` uses max's deploy key and root
  # never needs an SSH identity. nixos-rebuild still evaluates as root, and
  # libgit2 refuses to open a repository it does not own without this.
  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };

  environment.systemPackages = with pkgs; [
    zfs
    smartmontools
    nvme-cli
    lm_sensors

    # Network tools — this host is a subnet router from Phase 3, so the
    # diagnosis kit is not optional.
    tcpdump
    nmap
    iperf3
  ];

  system.stateVersion = "26.11";
}
