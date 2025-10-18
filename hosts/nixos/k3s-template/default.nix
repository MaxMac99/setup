{ config, pkgs, modulesPath, lib, ... }:

{
  imports =
    (map lib.custom.relativeToRoot [
      "hosts/common/core"
      "modules/nixos/k3s-base.nix"
    ])
    ++ [
      ./hardware-configuration.nix
    ];

  # System platform
  nixpkgs.hostPlatform = "x86_64-linux";

  # Host specification
  hostSpec = {
    username = "max";
    hostName = "k3s-template";
    isDarwin = false;
    isWork = false;
    isServer = true;
    isMinimal = true;
  };

  # Bootloader
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Networking (time zone is set in hosts/common/core)
  networking = {
    hostId = "00000000"; # Placeholder - cloud-init will set unique IDs
    useDHCP = false; # Static IPs configured via cloud-init
    firewall.enable = false; # K3S manages its own firewall rules
    nameservers = config.networkConfig.dns.servers;
  };

  # Enable cloud-init for VM customization
  services.cloud-init = {
    enable = true;
    network.enable = true;
  };

  # Additional system packages (basic packages from hosts/common/users/primary)
  environment.systemPackages = with pkgs; [
    htop
    wget
  ];

  # K3S service is enabled in k3s-base.nix
  # Cloud-init will configure role, token, etc.

  system.stateVersion = "24.11";
}