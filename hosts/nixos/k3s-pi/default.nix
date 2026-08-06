{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
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
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
      ];
    };
  };

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
