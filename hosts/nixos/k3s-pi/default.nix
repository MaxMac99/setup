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
    ++ (with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-4.base
      trusted-nix-caches
      inputs.nixos-raspberrypi.lib.inject-overlays
    ])
    ++ [./hardware-configuration.nix];

  nixpkgs.hostPlatform = "aarch64-linux";

  # Pi PoE+ HAT: enable the rpi-poe-plus DT overlay so the EMC2301 fan
  # controller and temperature-based fan curve work.
  hardware.raspberry-pi.config.all.dt-overlays.rpi-poe-plus = {
    enable = true;
    params = {};
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
        8123 # Home Assistant
      ];
    };
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

  services.home-assistant = {
    enable = true;
    config = {
      homeassistant = {
        name = "Home";
        time_zone = "Europe/Berlin";
        unit_system = "metric";
        country = "DE";
      };
      default_config = {};
    };
  };

  system.stateVersion = "25.11";
}
