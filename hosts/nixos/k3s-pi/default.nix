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
    # Integrations whose Python deps must be bundled.
    # Add only ones with devices you actually have on the network — each
    # rebuild of HA recompiles with these baked in.
    #
    # NOTE: with `config = null` (imperative/UI config), the module can no
    # longer scan configuration.yaml to discover which integrations to bundle,
    # so every integration you configure via the UI must be listed here.
    # `default_config` pulls in the standard set (frontend, history, the
    # automation/scene/script editors, mobile_app, zeroconf discovery, ...).
    extraComponents = [
      "default_config"
      "apple_tv"
      "google_translate"
      "homekit_controller"
      "hue"
      "matter"
      "met"
      "roborock"
      "sonos"
      "wled"
      "shelly"
      "unifi"
      "unifi_discovery"
    ];
    # null => Home Assistant owns configuration.yaml; everything is configured
    # from the UI. Setting `config` to an attrset would make NixOS write a
    # read-only configuration.yaml symlinked from the Nix store, which blocks
    # UI configuration. Core settings (name, time zone, country, units) are
    # set during UI onboarding / Settings → System → General.
    config = null;
  };

  services.matter-server = {
    enable = true;
  };

  system.stateVersion = "25.11";
}
